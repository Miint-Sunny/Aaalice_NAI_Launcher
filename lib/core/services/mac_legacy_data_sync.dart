import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'adjacent_app_data_migration.dart';

/// What the previous-version data step does on this launch.
enum MacLegacyDataTask {
  /// First launch: copy the previous version's data once.
  import,

  /// Settings → Sync from previous version: replace this version's data with
  /// a fresh copy, keeping a backup.
  sync,

  /// Settings → Undo last sync: switch back to the newest backup, the data
  /// from before the sync.
  undo,

  /// Settings → Switch back to synced data, offered after an undo: switch
  /// back to the backup the undo made, the data from after the sync.
  redo,
}

/// A sync, undo or redo the user asked for in Settings. Hive and the
/// databases are open while the app runs, so the request is carried out on
/// the next launch, before anything opens.
class MacLegacyDataRequest {
  const MacLegacyDataRequest.sync()
    : task = MacLegacyDataTask.sync,
      backup = null;

  const MacLegacyDataRequest.undo(String this.backup)
    : task = MacLegacyDataTask.undo;

  const MacLegacyDataRequest.redo(String this.backup)
    : task = MacLegacyDataTask.redo;

  final MacLegacyDataTask task;

  /// Undo or redo: the backup to switch back to.
  final String? backup;
}

/// This version's data as it was right before a sync, an undo or a redo.
class MacLegacyDataBackup {
  const MacLegacyDataBackup(this.directory, this.task, this.at);

  final Directory directory;

  /// The task the backup was made for: [MacLegacyDataTask.sync],
  /// [MacLegacyDataTask.undo] or [MacLegacyDataTask.redo].
  final MacLegacyDataTask task;
  final DateTime at;

  String get id => p.basename(directory.path);
}

/// Requests, backups and the folder switch behind "Sync from previous
/// version", "Undo last sync" and switching back to the synced data. Undo and
/// redo swap the data from before and after a sync back and forth: each
/// switch keeps the data it replaces as the newest backup.
///
/// A switch renames this version's data folder into
/// `<data folder>.backups/<time>-before-<task>`, moves the top-level entries
/// only this version has (Agent data, preference backups, …) from it into
/// the incoming folder, and renames the incoming folder into place. Every
/// step is a rename on the same disk, so nothing is copied twice and links
/// inside moved folders keep working. A journal next to the data folder
/// records the switch; the next launch completes or reverses a switch that a
/// crash interrupted. Only the newest [keep] backups are kept.
class MacLegacyDataSwitch {
  MacLegacyDataSwitch(
    this.destination, {
    DateTime Function()? clock,
    this.onStep,
  }) : _clock = clock ?? DateTime.now;

  static const keep = 2;

  final Directory destination;
  final DateTime Function() _clock;

  /// Test hook: called before each rename of a switch (`backup`, `carry`,
  /// `publish`); throwing there simulates a failure at that point.
  final Future<void> Function(String step)? onStep;

  String get _name => p.basename(destination.path);
  Directory get backupRoot =>
      Directory(p.join(destination.parent.path, '$_name.backups'));
  File get _request =>
      File(p.join(destination.parent.path, '.$_name.sync-request.json'));
  File get _journal =>
      File(p.join(destination.parent.path, '.$_name.sync-journal.json'));

  static final _backupName = RegExp(
    r'^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})-(\d{3})-before-(sync|undo|redo)$',
  );

  /// A request or an interrupted switch waits for this launch.
  Future<bool> pending() async =>
      await _request.exists() || await _journal.exists();

  Future<MacLegacyDataRequest?> readRequest() async {
    if (!await _request.exists()) return null;
    try {
      final value = jsonDecode(await _request.readAsString());
      if (value is Map) {
        final backup = value['backup'];
        switch (MacLegacyDataTask.values.asNameMap()[value['task']]) {
          case MacLegacyDataTask.sync:
            return const MacLegacyDataRequest.sync();
          case MacLegacyDataTask.undo when backup is String:
            return MacLegacyDataRequest.undo(backup);
          case MacLegacyDataTask.redo when backup is String:
            return MacLegacyDataRequest.redo(backup);
          case _:
        }
      }
    } on FormatException {
      // Unreadable: treated as no request, and removed below.
    }
    await clearRequest();
    return null;
  }

  Future<void> writeRequest(MacLegacyDataRequest request) async {
    await destination.parent.create(recursive: true);
    await _request.writeAsString(
      jsonEncode({
        'task': request.task.name,
        if (request.backup != null) 'backup': request.backup,
        'at': _clock().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<void> clearRequest() async {
    if (await _request.exists()) await _request.delete();
  }

  /// Newest first. Only real folders with the backup name pattern count.
  Future<List<MacLegacyDataBackup>> backups() async {
    if (!await backupRoot.exists()) return const [];
    final result = <MacLegacyDataBackup>[];
    await for (final entry in backupRoot.list(followLinks: false)) {
      final match = _backupName.firstMatch(p.basename(entry.path));
      if (match == null ||
          await FileSystemEntity.type(entry.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        continue;
      }
      final [year, month, day, hour, minute, second, millisecond] = [
        for (var group = 1; group <= 7; group++) int.parse(match[group]!),
      ];
      result.add(
        MacLegacyDataBackup(
          Directory(entry.path),
          MacLegacyDataTask.values.byName(match[8]!),
          DateTime(year, month, day, hour, minute, second, millisecond),
        ),
      );
    }
    return result..sort((a, b) => b.id.compareTo(a.id));
  }

  /// Removes all but the newest [keep] backups.
  Future<void> prune() async {
    for (final backup in (await backups()).skip(keep)) {
      await deleteFolderQuietly(backup.directory);
    }
  }

  /// Puts [incoming] in place of the data folder. The current data becomes
  /// a backup made before [task] (none when the folder is empty), and its
  /// top-level entries that [incoming] lacks move over with it. On failure
  /// everything is moved back and the error is rethrown.
  Future<MacLegacyDataBackup?> switchTo(
    Directory incoming, {
    required MacLegacyDataTask task,
    required bool incomingIsBackup,
  }) async {
    if (await isEmptyDataFolder(destination)) {
      await publishDataFolder(incoming, destination);
      return null;
    }
    await backupRoot.create(recursive: true);
    final at = _clock();
    final backup = await _freeBackupDirectory(at, task);
    final carry = await _onlyIn(destination, notIn: incoming);
    await _journal.writeAsString(
      jsonEncode({
        'task': task.name,
        'incoming': incoming.absolute.path,
        'incomingIsBackup': incomingIsBackup,
        'backup': backup.absolute.path,
        'carry': carry,
      }),
      flush: true,
    );
    var movedCurrent = false;
    final carried = <String>[];
    try {
      await onStep?.call('backup');
      await destination.rename(backup.path);
      movedCurrent = true;
      for (final name in carry) {
        await onStep?.call('carry');
        await _move(p.join(backup.path, name), p.join(incoming.path, name));
        carried.add(name);
      }
      await onStep?.call('publish');
      await publishDataFolder(incoming, destination);
    } catch (error, stackTrace) {
      try {
        for (final name in carried.reversed) {
          await _move(p.join(incoming.path, name), p.join(backup.path, name));
        }
        if (movedCurrent) {
          if (await destination.exists()) await destination.delete();
          await backup.rename(destination.path);
        }
        await _journal.delete();
      } catch (_) {
        // The journal stays; the next launch finishes putting it back.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    await _journal.delete();
    return MacLegacyDataBackup(backup, task, at);
  }

  /// Completes or reverses a switch a crash interrupted. Returns true when
  /// the switch is now complete (its request is done).
  Future<bool> recover() async {
    if (!await _journal.exists()) return false;
    final Directory incoming;
    final Directory backup;
    final List<String> carry;
    final bool incomingIsBackup;
    try {
      final journal = jsonDecode(await _journal.readAsString()) as Map;
      incoming = Directory(journal['incoming'] as String);
      backup = Directory(journal['backup'] as String);
      carry = [...(journal['carry'] as List).cast<String>()];
      incomingIsBackup = journal['incomingIsBackup'] == true;
    } on Object {
      // Not written by a switch that got as far as moving anything.
      await _journal.delete();
      return false;
    }
    final hasCurrent = !await isEmptyDataFolder(destination);
    if (await incoming.exists()) {
      if (!hasCurrent && await backup.exists()) {
        // The data folder was already moved away: finish the switch.
        for (final name in carry) {
          final from = p.join(backup.path, name);
          final to = p.join(incoming.path, name);
          if (await _exists(from) && !await _exists(to)) await _move(from, to);
        }
        await publishDataFolder(incoming, destination);
        await _journal.delete();
        return true;
      }
      // Nothing was moved yet: drop a staging copy, never a backup.
      if (!incomingIsBackup) await deleteFolderQuietly(incoming);
      await _journal.delete();
      return false;
    }
    if (hasCurrent) {
      await _journal.delete();
      return true;
    }
    if (await backup.exists()) await publishDataFolder(backup, destination);
    await _journal.delete();
    return false;
  }

  Future<Directory> _freeBackupDirectory(
    DateTime at,
    MacLegacyDataTask task,
  ) async {
    var stamp = at;
    while (true) {
      String two(int value) => value.toString().padLeft(2, '0');
      final name =
          '${stamp.year.toString().padLeft(4, '0')}${two(stamp.month)}'
          '${two(stamp.day)}-${two(stamp.hour)}${two(stamp.minute)}'
          '${two(stamp.second)}-'
          '${stamp.millisecond.toString().padLeft(3, '0')}-before-${task.name}';
      final directory = Directory(p.join(backupRoot.path, name));
      if (!await _exists(directory.path)) return directory;
      stamp = stamp.add(const Duration(milliseconds: 1));
    }
  }

  /// Top-level entries of [root] that [notIn] lacks, apart from the marker
  /// and Finder files, which belong to each folder.
  static Future<List<String>> _onlyIn(
    Directory root, {
    required Directory notIn,
  }) async {
    final names = <String>[];
    await for (final entry in root.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (name == AdjacentAppDataMigration.markerName || name == _finderFile) {
        continue;
      }
      if (!await _exists(p.join(notIn.path, name))) names.add(name);
    }
    return names..sort();
  }

  static Future<bool> _exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  static Future<void> _move(String from, String to) async {
    switch (await FileSystemEntity.type(from, followLinks: false)) {
      case FileSystemEntityType.directory:
        await Directory(from).rename(to);
      case FileSystemEntityType.link:
        await Link(from).rename(to);
      case FileSystemEntityType.notFound:
        throw FileSystemException('Entry to move is missing', from);
      default:
        await File(from).rename(to);
    }
  }
}

/// Finder writes this into any folder it shows; it is not user data.
const _finderFile = '.DS_Store';

/// Missing, or holding nothing but Finder files.
Future<bool> isEmptyDataFolder(Directory directory) async {
  if (!await directory.exists()) return true;
  await for (final entry in directory.list(followLinks: false)) {
    if (p.basename(entry.path) != _finderFile) return false;
  }
  return true;
}

/// Renames [incoming] into [destination], which must be missing or empty.
/// The destination is removed non-recursively, so anything that appeared in
/// it meanwhile stops the rename instead of being deleted.
Future<void> publishDataFolder(
  Directory incoming,
  Directory destination,
) async {
  if (await destination.exists()) {
    final finder = File(p.join(destination.path, _finderFile));
    if (await finder.exists()) await finder.delete();
    await destination.delete();
  }
  try {
    await incoming.rename(destination.path);
  } catch (_) {
    await destination.create(recursive: true);
    rethrow;
  }
}

/// Staging folders and old backups are this feature's own; one that cannot
/// be removed now is removed by a later attempt.
Future<void> deleteFolderQuietly(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } on FileSystemException {
    // Left for a later attempt.
  }
}
