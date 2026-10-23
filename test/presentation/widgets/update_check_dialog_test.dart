import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/update_installer_service.dart';
import 'package:nai_launcher/data/models/version/release_asset_info.dart';
import 'package:nai_launcher/data/models/version/version_info.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/update_provider.dart';
import 'package:nai_launcher/presentation/widgets/common/update_check_dialog.dart';

class _DialogUpdateNotifier extends UpdateStateNotifier {
  _DialogUpdateNotifier(this.initialState);

  final UpdateState initialState;
  var installRequests = 0;

  @override
  UpdateState build() => initialState;

  @override
  Future<void> installDownloadedUpdate() async => installRequests++;
}

/// 已下载、等待最后一步的更新弹窗。
Future<_DialogUpdateNotifier> _pumpDownloaded(
  WidgetTester tester,
  ReleaseAssetInfo asset, {
  required bool busy,
}) async {
  final info = VersionInfo(
    version: '2.1.0',
    currentVersion: '2.0.0',
    primaryAsset: asset,
    assets: [asset],
    isNewer: true,
  );
  final notifier = _DialogUpdateNotifier(
    UpdateState(
      status: UpdateStatus.downloaded,
      versionInfo: info,
      downloadedUpdate: DownloadedUpdate(
        file: File(asset.fileName),
        asset: asset,
        version: '2.1.0',
      ),
      notificationVisible: true,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        updateStateNotifierProvider.overrideWith(() => notifier),
        updateTaskBusyProvider.overrideWithValue(busy),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: UpdateCheckDialog()),
      ),
    ),
  );
  await tester.pump();
  return notifier;
}

void main() {
  testWidgets(
    'update dialog uses Preview labels and retains raw comparison versions',
    (tester) async {
      const info = VersionInfo(
        version: '2.0.0-preview',
        currentVersion: '2.0.0-preview+6',
        isNewer: true,
      );
      const state = UpdateState(
        status: UpdateStatus.available,
        versionInfo: info,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            updateStateNotifierProvider.overrideWith(
              () => _DialogUpdateNotifier(state),
            ),
            updateTaskBusyProvider.overrideWithValue(false),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(body: UpdateCheckDialog()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('2.0 Preview'), findsNWidgets(2));
      expect(find.text('2.0.0-preview'), findsNothing);
      expect(find.text('2.0.0-preview+6'), findsNothing);
      expect(info.currentVersion, '2.0.0-preview+6');
      expect(info.version, '2.0.0-preview');
    },
  );

  testWidgets('renders GitHub Flavored Markdown release notes', (tester) async {
    const asset = ReleaseAssetInfo(
      type: ReleaseAssetType.windowsPortable,
      platform: 'windows',
      fileName: 'update.zip',
      downloadUrl: 'https://example.com/update.zip',
      sha256: 'abc',
    );
    const info = VersionInfo(
      version: '2.0.0',
      currentVersion: '1.0.0',
      primaryAsset: asset,
      assets: [asset],
      isNewer: true,
      releaseNotes: '''
# Major Update

- [x] Persistent notifications
- **Safe** rollback

| Feature | Status |
| --- | --- |
| Resume | Ready |

> Important note

```dart
print('updated');
```

[Release details](https://example.com/release)
''',
    );
    const state = UpdateState(
      status: UpdateStatus.available,
      versionInfo: info,
      notificationVisible: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateStateNotifierProvider.overrideWith(
            () => _DialogUpdateNotifier(state),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: UpdateCheckDialog()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text('Major Update'), findsOneWidget);
    expect(find.text('Persistent notifications'), findsOneWidget);
    expect(find.text('Feature'), findsOneWidget);
    expect(find.text('Important note'), findsOneWidget);
    expect(find.text("print('updated');"), findsOneWidget);
    expect(find.text('Release details'), findsOneWidget);
  });

  testWidgets('macOS finishes a downloaded update in Finder', (tester) async {
    const asset = ReleaseAssetInfo(
      type: ReleaseAssetType.macosPortable,
      platform: 'macos',
      fileName: 'WOF_NAI_Studio_macOS_2.1.0_Portable.zip',
      downloadUrl: 'https://example.com/macos.zip',
      sha256: 'abc',
      size: 100,
    );
    final notifier = await _pumpDownloaded(tester, asset, busy: true);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.text(l10n.updateDownloadedFinderHint('2.1.0')), findsOneWidget);
    expect(find.text(l10n.updateInstallAndRestart), findsNothing);
    // 在访达中显示不会关掉应用，生成任务进行中也可以点。
    expect(find.text(l10n.updateWaitForTask), findsNothing);

    await tester.tap(find.text(l10n.updateShowInFinder));
    await tester.pump();

    expect(notifier.installRequests, 1);
  });

  testWidgets('Windows waits for running tasks before restarting', (
    tester,
  ) async {
    const asset = ReleaseAssetInfo(
      type: ReleaseAssetType.windowsInstaller,
      platform: 'windows',
      fileName: 'WOF_NAI_Studio_Windows_2.1.0_Setup.exe',
      downloadUrl: 'https://example.com/setup.exe',
      sha256: 'abc',
      size: 100,
    );
    final notifier = await _pumpDownloaded(tester, asset, busy: true);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.text(l10n.updateDownloadedHint('2.1.0')), findsOneWidget);
    expect(find.text(l10n.updateShowInFinder), findsNothing);
    expect(find.text(l10n.updateWaitForTask), findsOneWidget);

    await tester.tap(find.text(l10n.updateInstallAndRestart));
    await tester.pump();

    expect(notifier.installRequests, 0);
  });
}
