import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/mac_legacy_data_import.dart';
import '../../../core/utils/app_support_directory.dart';
import '../../ui/settings/settings_contract.dart';

/// This install's previous-version data step, or null where Settings must
/// not offer a sync (not macOS, sandbox, tests, no previous app configured).
final macLegacyDataLocatorProvider =
    Provider<Future<MacLegacyDataImport?> Function()>(
      (ref) => locateMacLegacyData,
    );

/// The "Previous version" section of Settings → Backup; null hides it, also
/// when the previous version has no data.
final settingsLegacyDataProvider = FutureProvider<SettingsLegacyData?>((
  ref,
) async {
  try {
    final import = await ref.watch(macLegacyDataLocatorProvider)();
    final status = await import?.status();
    if (status == null) return null;
    final latest = status.backups.firstOrNull;
    final undo = latest?.task == MacLegacyDataTask.sync ? latest : null;
    final undone = latest?.task == MacLegacyDataTask.undo ? latest : null;
    return SettingsLegacyData(
      appName: macLegacyAppName,
      copiedAt: status.copiedAt,
      syncedAt: status.syncedAt,
      undoBackup: undo?.id,
      undoAt: undo?.at,
      undoneAt: undone?.at,
      running: status.legacyRunning,
    );
  } on Object {
    // Unreadable folders: hide the section rather than offer a broken sync.
    return null;
  }
});

/// The app refused to restart because a task is still running.
class SettingsLegacyBusy implements Exception {
  const SettingsLegacyBusy();
}

/// Records a sync or undo for the next launch, then restarts. If the restart
/// is refused (a generation or download is running) the request is dropped
/// again, so it never surprises the user on a later launch.
class SettingsLegacyActions {
  SettingsLegacyActions({required this.locate, required this.restart});

  final Future<MacLegacyDataImport?> Function() locate;

  /// Settings' restart: throws a [StateError] while a task is running.
  final Future<void> Function() restart;

  Future<void> sync() => _request(const MacLegacyDataRequest.sync());

  Future<void> undo(String backup) =>
      _request(MacLegacyDataRequest.undo(backup));

  Future<void> _request(MacLegacyDataRequest request) async {
    final import = await locate();
    if (import == null) {
      throw StateError('Previous version data is not available here');
    }
    await import.request(request);
    try {
      await restart();
    } on StateError {
      await import.cancelRequest();
      throw const SettingsLegacyBusy();
    } catch (_) {
      await import.cancelRequest();
      rethrow;
    }
  }
}
