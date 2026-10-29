import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/mac_legacy_data_import.dart';
import 'package:nai_launcher/core/services/mac_legacy_data_sync.dart';
import 'package:nai_launcher/core/utils/app_support_directory.dart';
import 'package:path/path.dart' as p;

import 'mac_legacy_data_test_support.dart';

void main() {
  late Directory fixture;
  late Directory support;
  late Directory legacy;
  late Directory target;
  late DateTime now;

  setUp(() async {
    // A synthetic ~/Library/Application Support. Never the real folders.
    fixture = await Directory.systemTemp.createTemp('mac-legacy-sync-test-');
    support = Directory(p.join(fixture.path, 'Application Support'));
    legacy = Directory(p.join(support.path, 'com.aaalice.naiLauncher'));
    target = Directory(p.join(support.path, 'com.wof.naiStudio'));
    now = DateTime(2026, 10, 29, 14);
    await writeData(legacy, 'hive/settings.hive', '1.1.1 latest settings');
    await writeData(legacy, 'hive/history.hive', '1.1.1 history');
    await writeData(legacy, 'databases/danbooru.db', '1.1.1 gallery');
    // This version, after the first-launch copy and some use.
    await writeData(
      target,
      MacLegacyDataImport.markerName,
      jsonEncode({'state': 'imported', 'at': '2026-10-23T06:05:00.000Z'}),
    );
    await writeData(target, 'hive/settings.hive', '2.0 settings');
    await writeData(target, 'hive/prompt_blocks.hive', '2.0 blocks');
    await writeData(target, 'agent-data/session.json', 'agent session');
    await writeData(target, 'settings_backups/v2/a.json', 'preference backup');
    await writeData(target, 'draft-backups/draft.json', 'draft');
  });
  tearDown(() => fixture.delete(recursive: true));

  MacLegacyDataImport import({
    bool Function()? running,
    Future<void> Function()? beforeCommit,
    Future<void> Function(String step)? onStep,
    Future<int> Function()? preferences,
  }) => MacLegacyDataImport(
    legacy: legacy,
    destination: target,
    isLegacyRunning: (_) async => running?.call() ?? false,
    beforeCommit: beforeCommit,
    preferences: preferences,
    dataSwitch: MacLegacyDataSwitch(
      target,
      clock: () => now = now.add(const Duration(minutes: 1)),
      onStep: onStep,
    ),
  );

  Future<String> read(Directory root, String relative) =>
      File(p.join(root.path, relative)).readAsString();

  Future<bool> exists(Directory root, String relative) async =>
      await FileSystemEntity.type(
        p.join(root.path, relative),
        followLinks: false,
      ) !=
      FileSystemEntityType.notFound;

  Future<Map<String, Object?>> marker() async =>
      jsonDecode(await read(target, MacLegacyDataImport.markerName))
          as Map<String, Object?>;

  Future<List<String>> leftovers() async => [
    await for (final entry in support.list())
      if (p.basename(entry.path).startsWith('.com.wof.naiStudio.import-') ||
          p.basename(entry.path).endsWith('.sync-journal.json'))
        p.basename(entry.path),
  ];

  Future<MacLegacyDataImportResult> sync() async {
    await import().request(const MacLegacyDataRequest.sync());
    return import().prepare();
  }

  /// Undo or redo to the newest backup, as Settings offers it.
  Future<MacLegacyDataImportResult> switchBack(
    MacLegacyDataRequest Function(String backup) request,
  ) async {
    final newest = (await import().dataSwitch.backups()).first;
    await import().request(request(newest.id));
    return import().prepare();
  }

  Future<List<MacLegacyDataTask>> backupTasks() async => [
    for (final backup in await import().dataSwitch.backups()) backup.task,
  ];

  test('a sync replaces the data, keeps a backup and moves this version\'s '
      'own folders over', () async {
    final original = await treeOf(legacy);

    final result = await sync();

    expect(result.state, MacLegacyDataState.synced);
    expect(result.task, MacLegacyDataTask.sync);
    expect(await read(target, 'hive/settings.hive'), '1.1.1 latest settings');
    expect(await read(target, 'databases/danbooru.db'), '1.1.1 gallery');
    // Folders only this version has came along unchanged.
    expect(await read(target, 'agent-data/session.json'), 'agent session');
    expect(
      await read(target, 'settings_backups/v2/a.json'),
      'preference backup',
    );
    expect(await read(target, 'draft-backups/draft.json'), 'draft');
    // hive/ is replaced as a whole; its 2.0 boxes stay in the backup.
    expect(await exists(target, 'hive/prompt_blocks.hive'), isFalse);
    expect((await marker())['state'], 'synced');

    final backups = await import().dataSwitch.backups();
    expect(backups, hasLength(1));
    expect(backups.single.task, MacLegacyDataTask.sync);
    final backup = backups.single.directory;
    expect(await read(backup, 'hive/settings.hive'), '2.0 settings');
    expect(await read(backup, 'hive/prompt_blocks.hive'), '2.0 blocks');
    expect(await exists(backup, 'agent-data'), isFalse);

    expect(await treeOf(legacy), original);
    expect(await import().dataSwitch.pending(), isFalse);
    expect(await leftovers(), isEmpty);
    expect((await import().prepare()).state, MacLegacyDataState.prepared);
  });

  test('only the newest two backups are kept', () async {
    for (final version in ['v1', 'v2', 'v3']) {
      await writeData(target, 'hive/settings.hive', version);
      expect((await sync()).state, MacLegacyDataState.synced);
    }

    final backups = await import().dataSwitch.backups();
    expect(backups, hasLength(MacLegacyDataSwitch.keep));
    expect(
      [
        for (final backup in backups)
          await read(backup.directory, 'hive/settings.hive'),
      ],
      ['v3', 'v2'],
    );
    expect(
      await import().dataSwitch.backupRoot.list().length,
      MacLegacyDataSwitch.keep,
    );
  });

  test('undo switches back and keeps the synced data as a backup', () async {
    await sync();
    await writeData(target, 'hive/settings.hive', 'edited after the sync');
    await writeData(target, 'agent-data/session.json', 'newer agent session');
    final syncBackup = (await import().dataSwitch.backups()).single;

    await import().request(MacLegacyDataRequest.undo(syncBackup.id));
    final result = await import().prepare();

    expect(result.state, MacLegacyDataState.undone);
    expect(await read(target, 'hive/settings.hive'), '2.0 settings');
    expect(await read(target, 'hive/prompt_blocks.hive'), '2.0 blocks');
    // This version's own folders keep their newest state.
    expect(
      await read(target, 'agent-data/session.json'),
      'newer agent session',
    );
    expect((await marker())['state'], 'imported');

    final backups = await import().dataSwitch.backups();
    expect(backups.single.task, MacLegacyDataTask.undo);
    expect(
      await read(backups.single.directory, 'hive/settings.hive'),
      'edited after the sync',
    );
    expect(await syncBackup.directory.exists(), isFalse);
    expect(await import().dataSwitch.pending(), isFalse);
  });

  test(
    'undo and switching back swap the two sides and keep later changes',
    () async {
      final original = await treeOf(legacy);
      Future<void> expectBackups(List<MacLegacyDataTask> tasks) async {
        expect(await backupTasks(), tasks);
        expect(
          await import().dataSwitch.backupRoot.list().length,
          lessThanOrEqualTo(MacLegacyDataSwitch.keep),
        );
      }

      // Sync, then keep working in this version.
      expect((await sync()).state, MacLegacyDataState.synced);
      await writeData(target, 'hive/settings.hive', 'changed after the sync');
      await writeData(target, 'hive/history.hive', 'history after the sync');
      await writeData(target, 'agent-data/session.json', 'agent session 2');
      await expectBackups([MacLegacyDataTask.sync]);

      // Undo: the data from before the sync.
      var result = await switchBack(MacLegacyDataRequest.undo);
      expect(result.state, MacLegacyDataState.undone);
      expect(result.task, MacLegacyDataTask.undo);
      expect(await read(target, 'hive/settings.hive'), '2.0 settings');
      expect(await read(target, 'hive/prompt_blocks.hive'), '2.0 blocks');
      expect(await exists(target, 'hive/history.hive'), isFalse);
      expect((await marker())['state'], 'imported');
      await expectBackups([MacLegacyDataTask.undo]);
      await writeData(target, 'hive/settings.hive', 'changed after the undo');

      // Switch back: the synced data, with what changed after the sync.
      result = await switchBack(MacLegacyDataRequest.redo);
      expect(result.state, MacLegacyDataState.redone);
      expect(result.task, MacLegacyDataTask.redo);
      expect(
        await read(target, 'hive/settings.hive'),
        'changed after the sync',
      );
      expect(await read(target, 'hive/history.hive'), 'history after the sync');
      expect(await read(target, 'databases/danbooru.db'), '1.1.1 gallery');
      expect(await exists(target, 'hive/prompt_blocks.hive'), isFalse);
      expect((await marker())['state'], 'synced');
      await expectBackups([MacLegacyDataTask.redo]);

      // Undo again: the data from before the sync, with its own later change.
      result = await switchBack(MacLegacyDataRequest.undo);
      expect(result.state, MacLegacyDataState.undone);
      expect(
        await read(target, 'hive/settings.hive'),
        'changed after the undo',
      );
      expect(await read(target, 'hive/prompt_blocks.hive'), '2.0 blocks');
      expect(await exists(target, 'hive/history.hive'), isFalse);
      await expectBackups([MacLegacyDataTask.undo]);
      final synced = (await import().dataSwitch.backups()).single.directory;
      expect(
        await read(synced, 'hive/settings.hive'),
        'changed after the sync',
      );
      expect(await read(synced, 'hive/history.hive'), 'history after the sync');

      // This version's own folders followed every switch.
      expect(await read(target, 'agent-data/session.json'), 'agent session 2');
      expect(
        await read(target, 'settings_backups/v2/a.json'),
        'preference backup',
      );
      expect(await exists(synced, 'agent-data'), isFalse);
      expect(await treeOf(legacy), original);
      expect(await import().dataSwitch.pending(), isFalse);
      expect(await leftovers(), isEmpty);
    },
  );

  test('backups from syncs, undos and redos count together', () async {
    await sync();
    await switchBack(MacLegacyDataRequest.undo);
    await sync();
    expect(await backupTasks(), [
      MacLegacyDataTask.sync,
      MacLegacyDataTask.undo,
    ]);

    // The third backup pushes out the oldest, whatever made it.
    await sync();
    expect(await backupTasks(), [
      MacLegacyDataTask.sync,
      MacLegacyDataTask.sync,
    ]);

    // Undo and redo each use up the backup they switch to.
    await switchBack(MacLegacyDataRequest.undo);
    await switchBack(MacLegacyDataRequest.redo);
    expect(await backupTasks(), [
      MacLegacyDataTask.redo,
      MacLegacyDataTask.sync,
    ]);
    await sync();
    expect(await backupTasks(), [
      MacLegacyDataTask.sync,
      MacLegacyDataTask.redo,
    ]);
    expect(
      await import().dataSwitch.backupRoot.list().length,
      MacLegacyDataSwitch.keep,
    );
  });

  test('a sync that fails while copying changes nothing', () async {
    final before = await treeOf(target);

    await import().request(const MacLegacyDataRequest.sync());
    final failed = await import(
      beforeCommit: () async =>
          throw const FileSystemException('synthetic copy failure'),
    ).prepare();

    expect(failed.state, MacLegacyDataState.failed);
    expect(failed.task, MacLegacyDataTask.sync);
    expect(await treeOf(target), before);
    expect(await import().dataSwitch.backups(), isEmpty);
    expect(await leftovers(), isEmpty);

    // Starting without syncing drops the request; nothing happens later.
    await import().skip();
    expect(await import().dataSwitch.pending(), isFalse);
    expect((await import().prepare()).state, MacLegacyDataState.prepared);
    expect(await treeOf(target), before);
  });

  for (final (step, failAt) in [('backup', 1), ('carry', 2), ('publish', 1)]) {
    test('a sync that fails at "$step" is rolled back completely', () async {
      final before = await treeOf(target);
      var calls = 0;

      await import().request(const MacLegacyDataRequest.sync());
      final failed = await import(
        onStep: (current) async {
          if (current == step && ++calls == failAt) {
            throw const FileSystemException('synthetic switch failure');
          }
        },
      ).prepare();

      expect(failed.state, MacLegacyDataState.failed);
      expect(await treeOf(target), before);
      expect(await import().dataSwitch.backups(), isEmpty);
      expect(await leftovers(), isEmpty);
      // Retrying later works.
      expect((await import().prepare()).state, MacLegacyDataState.synced);
    });
  }

  test('a switch a crash interrupted is finished on the next launch', () async {
    // The state right after the old data moved into its backup and one of
    // this version's folders moved into the new data.
    final backup = Directory(
      p.join(
        support.path,
        'com.wof.naiStudio.backups',
        '20261029-140000-000-before-sync',
      ),
    );
    final staging = Directory(
      p.join(support.path, '.com.wof.naiStudio.import-crash'),
    );
    await writeData(staging, 'hive/settings.hive', '1.1.1 latest settings');
    await writeData(
      staging,
      MacLegacyDataImport.markerName,
      jsonEncode({'state': 'synced', 'at': '2026-10-29T06:00:00.000Z'}),
    );
    await backup.parent.create(recursive: true);
    await target.rename(backup.path);
    await Directory(
      p.join(backup.path, 'agent-data'),
    ).rename(p.join(staging.path, 'agent-data'));
    // path_provider creates the folder again before anything else runs.
    await target.create();
    await import().request(const MacLegacyDataRequest.sync());
    await File(
      p.join(support.path, '.com.wof.naiStudio.sync-journal.json'),
    ).writeAsString(
      jsonEncode({
        'task': 'sync',
        'incoming': staging.path,
        'incomingIsBackup': false,
        'backup': backup.path,
        'carry': ['agent-data', 'draft-backups', 'settings_backups'],
      }),
    );

    expect((await import().prepare()).state, MacLegacyDataState.prepared);

    expect(await read(target, 'hive/settings.hive'), '1.1.1 latest settings');
    expect(await read(target, 'agent-data/session.json'), 'agent session');
    expect(await read(target, 'draft-backups/draft.json'), 'draft');
    expect(
      await read(target, 'settings_backups/v2/a.json'),
      'preference backup',
    );
    expect(await read(backup, 'hive/settings.hive'), '2.0 settings');
    expect(await import().dataSwitch.pending(), isFalse);
    expect(await leftovers(), isEmpty);
  });

  test(
    'a switch interrupted before anything moved is simply retried',
    () async {
      final staging = Directory(
        p.join(support.path, '.com.wof.naiStudio.import-crash'),
      );
      await writeData(staging, 'hive/settings.hive', 'stale copy');
      await import().request(const MacLegacyDataRequest.sync());
      await File(
        p.join(support.path, '.com.wof.naiStudio.sync-journal.json'),
      ).writeAsString(
        jsonEncode({
          'task': 'sync',
          'incoming': staging.path,
          'incomingIsBackup': false,
          'backup': p.join(support.path, 'com.wof.naiStudio.backups', 'x'),
          'carry': ['agent-data'],
        }),
      );

      expect((await import().prepare()).state, MacLegacyDataState.synced);
      expect(await read(target, 'hive/settings.hive'), '1.1.1 latest settings');
      expect(await read(target, 'agent-data/session.json'), 'agent session');
      expect(await leftovers(), isEmpty);
    },
  );

  test('a sync waits while the old app runs and can be dropped', () async {
    await import().request(const MacLegacyDataRequest.sync());
    var checks = 0;
    final waiting = RecordingPresenter();

    expect(
      await runMacLegacyDataImport(
        import(running: () => ++checks < 3),
        presenter: waiting,
        pollInterval: Duration.zero,
        settleDelay: Duration.zero,
      ),
      MacLegacyDataState.synced,
    );
    expect(waiting.calls, ['running:sync', 'copying:sync', 'starting']);

    await import().request(const MacLegacyDataRequest.sync());
    final dropped = RecordingPresenter(skipWhenRunning: true);
    expect(
      await runMacLegacyDataImport(
        import(running: () => true),
        presenter: dropped,
        pollInterval: const Duration(milliseconds: 5),
      ),
      MacLegacyDataState.skipped,
    );
    expect(dropped.calls, ['running:sync', 'starting']);
    expect(await import().dataSwitch.pending(), isFalse);
    expect(await import().dataSwitch.backups(), hasLength(1));
  });

  test('a failed sync offers retry and dropping it', () async {
    await import().request(const MacLegacyDataRequest.sync());
    var attempts = 0;
    final presenter = RecordingPresenter(retry: true);

    final state = await runMacLegacyDataImport(
      import(
        beforeCommit: () async {
          if (attempts++ == 0) {
            throw const FileSystemException('synthetic copy failure');
          }
        },
      ),
      presenter: presenter,
    );

    expect(state, MacLegacyDataState.synced);
    expect(presenter.calls, [
      'copying:sync',
      'failed:sync',
      'copying:sync',
      'starting',
    ]);
  });

  test('settings see the data source, backups and a running old app', () async {
    final first = await import(running: () => true).status();
    expect(first!.copiedAt, DateTime.utc(2026, 10, 23, 6, 5).toLocal());
    expect(first.syncedAt, isNull);
    expect(first.backups, isEmpty);
    expect(first.legacyRunning, isTrue);

    await import().request(const MacLegacyDataRequest.sync());
    expect((await import().status())!.pending?.task, MacLegacyDataTask.sync);
    await import().prepare();
    final synced = (await import().status())!;
    expect(synced.syncedAt, isNotNull);
    expect(synced.copiedAt, isNull);
    expect(synced.backups.single.task, MacLegacyDataTask.sync);
  });

  test('without previous data there is nothing to show or sync', () async {
    await legacy.delete(recursive: true);
    expect(await import().status(), isNull);

    await import().request(const MacLegacyDataRequest.sync());
    final failed = await import().prepare();
    expect(failed.state, MacLegacyDataState.failed);
    expect(await read(target, 'hive/settings.hive'), '2.0 settings');
  });

  test('the sync is offered only on macOS outside a sandbox', () {
    for (final (layout, sandbox, offered) in [
      (SupportDirectoryLayout.macLegacyImport, null, true),
      (SupportDirectoryLayout.macLegacyImport, '/tmp/sandbox', false),
      (SupportDirectoryLayout.executableAdjacent, null, false),
      (SupportDirectoryLayout.system, null, false),
    ]) {
      expect(
        macLegacySyncOffered(layout: layout, sandboxRoot: sandbox),
        offered,
        reason: '$layout $sandbox',
      );
    }
  });
}
