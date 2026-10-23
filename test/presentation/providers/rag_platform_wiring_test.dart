import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/rag/rag_client.dart';
import 'package:nai_launcher/core/rag/rag_platform.dart';
import 'package:nai_launcher/core/rag/rag_settings.dart';
import 'package:nai_launcher/presentation/providers/rag_model_download_provider.dart';
import 'package:nai_launcher/presentation/providers/rag_provider.dart';
import 'package:nai_launcher/presentation/ui/settings/settings_contract.dart';
import 'package:nai_launcher/presentation/wiring/settings/settings_rag.dart';
import 'package:path/path.dart' as p;

class _Settings extends RagSettingsController {
  @override
  RagSettings build() => const RagSettings(
    enabled: true,
    tagsEnabled: false,
    wikiEnabled: true,
    embedding: 'embedding',
    reranker: 'reranker',
  );
}

void main() {
  test('settings project the platform and whether it can install', () {
    SettingsRagData project(RagPlatform platform) => settingsRagData(
      const RagSettings(),
      const RagStatus(),
      const AsyncLoading(),
      const RagModelDownloadState(),
      const SettingsRagSessionState(),
      null,
      platform: platform,
    );
    final windows = project(RagPlatform.windows);
    expect(windows.platform, SettingsRagPlatform.windows);
    expect((windows.runtimeSupported, windows.cudaSupported), (true, true));
    final arm = project(RagPlatform.macOSArm64);
    expect(arm.platform, SettingsRagPlatform.macOS);
    expect((arm.runtimeSupported, arm.cudaSupported), (true, false));
    final intel = project(RagPlatform.macOSX64);
    expect(intel.platform, SettingsRagPlatform.macOS);
    expect((intel.runtimeSupported, intel.cudaSupported), (false, false));
  });

  for (final (platform, layout) in [
    (RagPlatform.windows, ['runtime', 'Scripts', 'python.exe']),
    (RagPlatform.macOSArm64, ['runtime', 'bin', 'python3']),
  ]) {
    test(
      '${platform.name} opens the managed interpreter of its venv',
      () async {
        final root = await Directory.systemTemp.createTemp('rag-platform-');
        addTearDown(() => root.delete(recursive: true));
        final managed = p.joinAll([root.path, ...layout]);
        File(managed).createSync(recursive: true);
        final started = <String>{};
        final container = ProviderContainer(
          overrides: [
            ragPlatformProvider.overrideWithValue(platform),
            ragSettingsProvider.overrideWith(_Settings.new),
            ragDirectoryProvider.overrideWithValue(() async => root),
            ragSourcePathsProvider.overrideWithValue(
              () async => (catalog: '', runtime: '', wiki: ''),
            ),
            ragClientStarterProvider.overrideWithValue(({
              required python,
              required directory,
            }) async {
              started.add(python);
              throw const RagException('fixture_stop');
            }),
          ],
        );
        addTearDown(container.dispose);
        expect(
          container.read(ragRuntimeProbeFactoryProvider)().platform,
          platform,
        );
        await container.read(ragControllerProvider.notifier).refresh();
        expect(started, {managed});
      },
    );
  }
}
