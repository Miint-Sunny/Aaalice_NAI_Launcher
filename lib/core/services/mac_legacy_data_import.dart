import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'adjacent_app_data_migration.dart';
import 'verified_directory_copy.dart';

/// What one first-launch check found or did.
enum MacLegacyDataState {
  /// An earlier launch already decided; nothing was checked again.
  prepared,

  /// This version already had data of its own; nothing was copied.
  existingData,

  /// There is no previous version data; this version starts empty.
  fresh,

  /// The previous version's data was copied.
  imported,

  /// The user chose to start without the previous version's data.
  skipped,

  /// The previous version is running; nothing was changed.
  legacyRunning,

  /// Copying failed and was undone; nothing was changed.
  failed,
}

class MacLegacyDataImportResult {
  const MacLegacyDataImportResult(this.state, [this.error]);

  final MacLegacyDataState state;
  final Object? error;

  /// The user has to quit the previous version, retry or skip.
  bool get needsDecision =>
      state == MacLegacyDataState.legacyRunning ||
      state == MacLegacyDataState.failed;
}

/// Copies the previous macOS version's settings, history and libraries on
/// first launch.
///
/// The previous version (W.O.F 1.x and the upstream NAI Launcher, bundle
/// `com.aaalice.naiLauncher`) keeps its data in its own Application Support
/// folder, which this version would otherwise never see. When this version's folder is still empty, the previous
/// folder is snapshotted, copied into a staging folder and verified file by
/// file, and only then renamed into place together with the
/// [AdjacentAppDataMigration.markerName] marker. The previous folder is only
/// read: it stays as it was and keeps working as a backup and for the
/// previous version itself. Unlike the Windows migration there is no
/// compatibility link and no second backup copy.
///
/// The marker makes this a one-time step: once it exists, later launches do
/// nothing. A failed attempt leaves neither a marker nor partial data, so
/// it can simply be repeated.
class MacLegacyDataImport {
  MacLegacyDataImport({
    required this.legacy,
    required this.destination,
    Future<bool> Function(Directory legacy)? isLegacyRunning,
    this.preferences,
    this.beforeCommit,
  }) : _isLegacyRunning = isLegacyRunning ?? hiveBoxesOpenElsewhere;

  static const markerName = AdjacentAppDataMigration.markerName;
  static const layout = 'macos-application-support';

  /// Finder writes this into any folder it shows; it is not user data.
  static const _finderFile = '.DS_Store';

  final Directory legacy;
  final Directory destination;
  final Future<bool> Function(Directory legacy) _isLegacyRunning;

  /// Copies the previous version's preferences that live outside the data
  /// folder; returns how many were copied. Runs once, after the folder copy.
  final Future<int> Function()? preferences;

  /// Test hook: runs after copying, before the previous folder is re-checked.
  final Future<void> Function()? beforeCommit;

  String get _name => p.basename(destination.path);
  String get _stagingPrefix => '.$_name.import-';
  File get _lockFile =>
      File(p.join(destination.parent.path, '.$_name.import.lock'));
  File get _markerFile => File(p.join(destination.path, markerName));

  Future<bool> isLegacyRunning() => _isLegacyRunning(legacy);

  /// The marker an earlier launch wrote, or null before the first decision.
  Future<Map<String, Object?>?> readMarker() async {
    if (!await _markerFile.exists()) return null;
    try {
      final value = jsonDecode(await _markerFile.readAsString());
      if (value is Map<String, Object?>) return value;
    } on FormatException {
      // A damaged marker still records that a decision was made.
    }
    return const {};
  }

  Future<MacLegacyDataImportResult> prepare({
    void Function()? onCopyStarted,
  }) async {
    _checkPaths();
    // Every launch after the first one: decided, nothing to lock or check.
    final marker = await readMarker();
    if (marker != null && marker['preferences'] != 'pending') {
      return const MacLegacyDataImportResult(MacLegacyDataState.prepared);
    }
    return _locked(() => _prepare(onCopyStarted));
  }

  /// Starts without the previous version's data; later launches do not ask
  /// or copy again.
  Future<void> skip() {
    _checkPaths();
    return _locked(() async {
      if (await readMarker() != null || !await _isEmpty(destination)) return;
      await destination.create(recursive: true);
      await _writeMarker(destination, state: MacLegacyDataState.skipped);
    });
  }

  void _checkPaths() {
    final oldPath = p.normalize(legacy.absolute.path);
    final newPath = p.normalize(destination.absolute.path);
    if (p.equals(oldPath, newPath) ||
        p.isWithin(oldPath, newPath) ||
        p.isWithin(newPath, oldPath)) {
      throw const FileSystemException('Application data paths overlap');
    }
  }

  /// Two launches at the same moment (for example `open -n`) take turns; the
  /// second one finds the first one's marker. The empty lock file stays, like
  /// the Windows migration lock, so no launch can ever lock a different file.
  Future<T> _locked<T>(Future<T> Function() body) async {
    await destination.parent.create(recursive: true);
    final lock = await _lockFile.open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      return await body();
    } finally {
      await lock.close();
    }
  }

  Future<MacLegacyDataImportResult> _prepare(
    void Function()? onCopyStarted,
  ) async {
    await _removeStaleStaging();
    if (await FileSystemEntity.type(destination.path, followLinks: false) ==
        FileSystemEntityType.link) {
      // A folder the user moved elsewhere on purpose is left alone.
      return const MacLegacyDataImportResult(MacLegacyDataState.existingData);
    }
    final marker = await readMarker();
    if (marker != null) {
      if (marker['state'] == MacLegacyDataState.imported.name &&
          marker['preferences'] == 'pending') {
        await _copyPreferences(marker);
      }
      return const MacLegacyDataImportResult(MacLegacyDataState.prepared);
    }
    if (!await _isEmpty(destination)) {
      await _writeMarker(destination, state: MacLegacyDataState.existingData);
      return const MacLegacyDataImportResult(MacLegacyDataState.existingData);
    }
    if (await _isEmpty(legacy)) {
      await destination.create(recursive: true);
      await _writeMarker(destination, state: MacLegacyDataState.fresh);
      return const MacLegacyDataImportResult(MacLegacyDataState.fresh);
    }
    if (await isLegacyRunning()) {
      return const MacLegacyDataImportResult(MacLegacyDataState.legacyRunning);
    }

    onCopyStarted?.call();
    Directory? staging;
    try {
      final snapshot = await snapshotDirectory(legacy, fileLinks: true);
      staging = await destination.parent.createTemp(_stagingPrefix);
      await copySnapshot(
        legacy,
        staging,
        snapshot,
        createLink: createRelativeLink,
      );
      await beforeCommit?.call();
      await verifySnapshot(legacy, snapshot, fileLinks: true);
      final files = snapshot.values.where((entry) => entry.isFile);
      await _writeMarker(
        staging,
        state: MacLegacyDataState.imported,
        details: {
          'files': files.length,
          'bytes': files.fold<int>(0, (sum, entry) => sum + entry.bytes),
          'preferences': preferences == null ? 'none' : 'pending',
        },
      );
      await _publish(staging);
      staging = null;
    } catch (error) {
      if (staging != null) await _deleteQuietly(staging);
      if (error is ApplicationDataChangedException && await isLegacyRunning()) {
        return const MacLegacyDataImportResult(
          MacLegacyDataState.legacyRunning,
        );
      }
      return MacLegacyDataImportResult(MacLegacyDataState.failed, error);
    }
    final published = await readMarker();
    if (published != null && published['preferences'] == 'pending') {
      await _copyPreferences(published);
    }
    return const MacLegacyDataImportResult(MacLegacyDataState.imported);
  }

  /// Swaps the verified staging folder in for the empty destination. The
  /// destination is removed non-recursively, so anything that appeared in it
  /// meanwhile stops the swap instead of being deleted.
  Future<void> _publish(Directory staging) async {
    if (await destination.exists()) {
      final finder = File(p.join(destination.path, _finderFile));
      if (await finder.exists()) await finder.delete();
      await destination.delete();
    }
    try {
      await staging.rename(destination.path);
    } catch (_) {
      await destination.create(recursive: true);
      rethrow;
    }
  }

  Future<void> _copyPreferences(Map<String, Object?> marker) async {
    final copy = preferences;
    if (copy == null) return;
    Map<String, Object?> result;
    try {
      result = {'preferences': 'imported', 'preferencesCopied': await copy()};
    } catch (error) {
      // Not retried automatically: later launches may already have changed
      // or removed preferences that a second copy would bring back.
      result = {'preferences': 'failed', 'preferencesError': '$error'};
    }
    try {
      await _markerFile.writeAsString(
        jsonEncode({...marker, ...result}),
        flush: true,
      );
    } on FileSystemException {
      // The data is in place; at worst the next launch copies the missing
      // preferences once more.
    }
  }

  Future<void> _writeMarker(
    Directory root, {
    required MacLegacyDataState state,
    Map<String, Object?> details = const {},
  }) async {
    await File(p.join(root.path, markerName)).writeAsString(
      jsonEncode({
        'schema': 1,
        'layout': layout,
        'state': state.name,
        'legacy': legacy.absolute.path,
        'at': DateTime.now().toUtc().toIso8601String(),
        ...details,
      }),
      flush: true,
    );
  }

  /// Leftovers of an attempt that was interrupted (for example the app was
  /// force quit while copying). Only real folders with this import's own
  /// prefix are removed; links are never followed.
  Future<void> _removeStaleStaging() async {
    await for (final entry in destination.parent.list(followLinks: false)) {
      if (!p.basename(entry.path).startsWith(_stagingPrefix)) continue;
      if (await FileSystemEntity.type(entry.path, followLinks: false) ==
          FileSystemEntityType.directory) {
        await _deleteQuietly(Directory(entry.path));
      }
    }
  }

  /// Staging folders are this import's own; one that cannot be removed now
  /// is removed by the next attempt.
  static Future<void> _deleteQuietly(Directory staging) async {
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
    } on FileSystemException {
      // Left for the next attempt.
    }
  }

  static Future<bool> _isEmpty(Directory directory) async {
    if (!await directory.exists()) return true;
    await for (final entry in directory.list(followLinks: false)) {
      if (p.basename(entry.path) != _finderFile) return false;
    }
    return true;
  }

  /// True while another process has a Hive box of [legacy] open. Hive holds
  /// an exclusive lock on `hive/<box>.lock` for as long as a box is open, and
  /// the previous version opens its boxes at startup and keeps them open
  /// until it quits. The probe takes a shared lock for an instant and never
  /// writes; lock files left behind by a crash are not locked.
  static Future<bool> hiveBoxesOpenElsewhere(Directory legacy) async {
    final hive = Directory(p.join(legacy.path, 'hive'));
    if (!await hive.exists()) return false;
    await for (final entry in hive.list(followLinks: false)) {
      if (entry is! File || p.extension(entry.path) != '.lock') continue;
      final RandomAccessFile file;
      try {
        file = await entry.open();
      } on FileSystemException {
        continue; // Removed while the box was being closed.
      }
      try {
        await file.lock(FileLock.shared);
        await file.unlock();
      } on FileSystemException {
        return true;
      } finally {
        await file.close();
      }
    }
    return false;
  }
}

/// Shows the first-launch copy in the window before the app itself starts.
abstract interface class MacLegacyDataImportPresenter {
  void showCopying();

  /// The previous version is open; copying continues by itself once it quits.
  void showLegacyRunning({required void Function() onSkip});

  void showFailed(
    Object error, {
    required void Function() onRetry,
    required void Function() onSkip,
  });

  /// The data is ready; the app is about to replace this screen.
  void showStarting();
}

/// Runs [import] until it is decided. Without a [presenter] a running
/// previous version or a failed copy stops startup, like the Windows
/// migration, and the next launch tries again.
Future<MacLegacyDataState> runMacLegacyDataImport(
  MacLegacyDataImport import, {
  MacLegacyDataImportPresenter? presenter,
  Duration pollInterval = const Duration(seconds: 1),
  Duration settleDelay = const Duration(seconds: 2),
}) async {
  var shown = false;
  Future<MacLegacyDataState> skip() async {
    try {
      await import.skip();
    } on FileSystemException {
      // Starting matters more than the marker. Without it the next launch
      // finds this version's own data and leaves it alone as well.
    }
    presenter?.showStarting();
    return MacLegacyDataState.skipped;
  }

  while (true) {
    MacLegacyDataImportResult result;
    try {
      result = await import.prepare(
        onCopyStarted: () {
          shown = true;
          presenter?.showCopying();
        },
      );
    } catch (error) {
      // Whatever went wrong, nothing was published: let the user decide.
      result = MacLegacyDataImportResult(MacLegacyDataState.failed, error);
    }
    if (!result.needsDecision) {
      if (shown) presenter?.showStarting();
      return result.state;
    }
    if (presenter == null) {
      throw result.error ??
          const FileSystemException(
            'The previous version is running; quit it and start again',
          );
    }
    shown = true;
    if (result.state == MacLegacyDataState.legacyRunning) {
      final skipped = Completer<void>();
      presenter.showLegacyRunning(
        onSkip: () {
          if (!skipped.isCompleted) skipped.complete();
        },
      );
      // A probe that cannot tell stops the wait; prepare() then reports it.
      Future<bool> stillRunning() =>
          import.isLegacyRunning().catchError((Object _) => false);
      while (!skipped.isCompleted && await stillRunning()) {
        await Future.any([skipped.future, Future<void>.delayed(pollInterval)]);
      }
      if (skipped.isCompleted) return skip();
      // The previous version closes its databases after its Hive boxes.
      await Future.any([skipped.future, Future<void>.delayed(settleDelay)]);
      if (skipped.isCompleted) return skip();
      continue;
    }
    final retry = Completer<bool>();
    presenter.showFailed(
      result.error!,
      onRetry: () {
        if (!retry.isCompleted) retry.complete(true);
      },
      onSkip: () {
        if (!retry.isCompleted) retry.complete(false);
      },
    );
    if (!await retry.future) return skip();
  }
}
