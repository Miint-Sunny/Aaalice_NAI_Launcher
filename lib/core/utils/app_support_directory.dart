import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as system_paths;

import '../services/adjacent_app_data_migration.dart';
import '../services/legacy_preferences_import.dart';
import '../services/mac_legacy_data_import.dart';
import 'app_logger.dart';

export 'package:path_provider/path_provider.dart'
    hide getApplicationSupportDirectory, getTemporaryDirectory;

Future<Directory>? _applicationSupportDirectory;

/// Bundle id of the previous macOS app whose data is copied on first launch
/// (W.O.F 1.x and the upstream NAI Launcher). A build can name another app
/// with `--dart-define=MAC_LEGACY_BUNDLE_ID=<bundle id>`; an empty value
/// turns the copy off.
const macLegacyBundleId = String.fromEnvironment(
  'MAC_LEGACY_BUNDLE_ID',
  defaultValue: 'com.aaalice.naiLauncher',
);

/// Shows the first-launch copy in the window. main() sets it before the
/// first call; without it a running previous version stops startup.
MacLegacyDataImportPresenter? macLegacyDataImportPresenter;

enum SupportDirectoryLayout {
  /// path_provider's folder, used as is (tests, Linux, macOS without a
  /// previous app).
  system,

  /// Windows: `user-data/` beside the executable, see
  /// [AdjacentAppDataMigration].
  executableAdjacent,

  /// macOS: path_provider's folder, filled once from the previous app, see
  /// [MacLegacyDataImport].
  macLegacyImport,
}

@visibleForTesting
SupportDirectoryLayout supportDirectoryLayoutFor({
  required bool isWindows,
  required bool isMacOS,
  required bool isTest,
  String legacyBundleId = macLegacyBundleId,
}) {
  if (isTest) return SupportDirectoryLayout.system;
  if (isWindows) return SupportDirectoryLayout.executableAdjacent;
  if (isMacOS && _isBundleId(legacyBundleId)) {
    return SupportDirectoryLayout.macLegacyImport;
  }
  return SupportDirectoryLayout.system;
}

bool _isBundleId(String value) =>
    value.isNotEmpty && !value.contains('/') && value != '.' && value != '..';

SupportDirectoryLayout get _layout => supportDirectoryLayoutFor(
  isWindows: Platform.isWindows,
  isMacOS: Platform.isMacOS,
  isTest: Platform.environment['FLUTTER_TEST'] == 'true',
);

bool get _usesAdjacentData =>
    _layout == SupportDirectoryLayout.executableAdjacent;

/// Windows internal state belongs to the executable, never the current working
/// directory. macOS copies the previous app's data in once before anything
/// opens. Tests retain the injected path_provider implementation.
Future<Directory> getApplicationSupportDirectory() {
  return switch (_layout) {
    SupportDirectoryLayout.executableAdjacent =>
      _applicationSupportDirectory ??= _prepareAdjacentData(),
    SupportDirectoryLayout.macLegacyImport =>
      _applicationSupportDirectory ??= _prepareMacData(),
    SupportDirectoryLayout.system =>
      system_paths.getApplicationSupportDirectory(),
  };
}

Future<Directory> _prepareAdjacentData() async {
  final destination = Directory(
    p.join(p.dirname(Platform.resolvedExecutable), 'user-data'),
  );
  return AdjacentAppDataMigration(
    legacy: await getLegacyApplicationSupportDirectory(),
    destination: destination,
  ).prepare();
}

Future<Directory> _prepareMacData() async {
  final destination = await system_paths.getApplicationSupportDirectory();
  final legacy = Directory(p.join(destination.parent.path, macLegacyBundleId));
  if (p.equals(legacy.path, destination.path)) return destination;
  final state = await runMacLegacyDataImport(
    MacLegacyDataImport(
      legacy: legacy,
      destination: destination,
      preferences: LegacyPreferencesImport.macOS(macLegacyBundleId).copyMissing,
    ),
    presenter: macLegacyDataImportPresenter,
  );
  AppLogger.i('Previous macOS app data: ${state.name}', 'Storage');
  return destination;
}

/// Only historical migration code may use the original Windows directory.
Future<Directory> getLegacyApplicationSupportDirectory() =>
    system_paths.getApplicationSupportDirectory();

Future<Directory> getTemporaryDirectory() async {
  if (!_usesAdjacentData) return system_paths.getTemporaryDirectory();
  return Directory(
    p.join((await getApplicationSupportDirectory()).path, 'temp'),
  ).create(recursive: true);
}
