import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/mac_legacy_data_import.dart';
import 'package:nai_launcher/core/services/mac_legacy_data_sync.dart';
import 'package:nai_launcher/core/utils/app_support_directory.dart';
import 'package:nai_launcher/presentation/ui/settings/settings_contract.dart';
import 'package:nai_launcher/presentation/wiring/settings/settings_legacy_data.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/mac_legacy_data_test_support.dart';

void main() {
  late Directory fixture;
  late Directory legacy;
  late Directory target;

  setUp(() async {
    // A synthetic ~/Library/Application Support. Never the real folders.
    fixture = await Directory.systemTemp.createTemp('settings-legacy-test-');
    final support = p.join(fixture.path, 'Application Support');
    legacy = Directory(p.join(support, 'com.aaalice.naiLauncher'));
    target = Directory(p.join(support, 'com.wof.naiStudio'));
    await writeData(legacy, 'hive/settings.hive', '1.1.1 settings');
    await writeData(
      target,
      MacLegacyDataImport.markerName,
      jsonEncode({'state': 'imported', 'at': '2026-10-23T06:05:00.000Z'}),
    );
    await writeData(target, 'hive/settings.hive', '2.0 settings');
  });
  tearDown(() => fixture.delete(recursive: true));

  MacLegacyDataImport import() => MacLegacyDataImport(
    legacy: legacy,
    destination: target,
    isLegacyRunning: (_) async => false,
  );

  Future<SettingsLegacyData?> read(
    MacLegacyDataImport? Function() locate,
  ) async {
    final container = ProviderContainer(
      overrides: [
        macLegacyDataLocatorProvider.overrideWithValue(() async => locate()),
      ],
    );
    addTearDown(container.dispose);
    return container.read(settingsLegacyDataProvider.future);
  }

  test('the section shows what the data came from', () async {
    final data = (await read(import))!;

    expect(data.appName, macLegacyAppName);
    expect(data.copiedAt, DateTime.utc(2026, 10, 23, 6, 5).toLocal());
    expect(data.syncedAt, isNull);
    expect(data.undoBackup, isNull);
    expect(data.running, isFalse);
  });

  test('undo is offered only right after a sync', () async {
    await import().request(const MacLegacyDataRequest.sync());
    await import().prepare();
    final backup = (await import().dataSwitch.backups()).single;
    final afterSync = (await read(import))!;
    expect(afterSync.undoBackup, backup.id);
    expect(afterSync.undoAt, backup.at);

    await import().request(MacLegacyDataRequest.undo(backup.id));
    await import().prepare();
    final afterUndo = (await read(import))!;
    expect(afterUndo.undoBackup, isNull);
    expect(afterUndo.undoneAt, isNotNull);
  });

  test('hidden off macOS, in a sandbox and without previous data', () async {
    // The locator gives nothing on Windows, in tests and in a sandbox
    // (macLegacySyncOffered), so the section disappears.
    expect(await read(() => null), isNull);
    expect(
      macLegacySyncOffered(
        layout: SupportDirectoryLayout.executableAdjacent,
        sandboxRoot: null,
      ),
      isFalse,
    );
    expect(
      macLegacySyncOffered(
        layout: SupportDirectoryLayout.macLegacyImport,
        sandboxRoot: '/tmp/sandbox',
      ),
      isFalse,
    );

    await legacy.delete(recursive: true);
    expect(await read(import), isNull);
  });

  test('sync records the request and restarts', () async {
    var restarts = 0;
    await SettingsLegacyActions(
      locate: () async => import(),
      restart: () async => restarts++,
    ).sync();

    expect(restarts, 1);
    expect(
      (await import().dataSwitch.readRequest())?.task,
      MacLegacyDataTask.sync,
    );
  });

  test('a refused restart drops the request again', () async {
    await expectLater(
      SettingsLegacyActions(
        locate: () async => import(),
        restart: () async => throw StateError('A task is running'),
      ).undo('20261029-140100-000-before-sync'),
      throwsA(isA<SettingsLegacyBusy>()),
    );
    expect(await import().dataSwitch.pending(), isFalse);
  });

  test('nothing can be synced where it is not offered', () async {
    var restarts = 0;
    await expectLater(
      SettingsLegacyActions(
        locate: () async => null,
        restart: () async => restarts++,
      ).sync(),
      throwsA(isA<StateError>()),
    );
    expect(restarts, 0);
    expect(await MacLegacyDataSwitch(target).pending(), isFalse);
  });
}
