import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/version/release_asset_info.dart';

void main() {
  group('ReleaseAssetInfo', () {
    test('detects Windows installer asset', () {
      final asset = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_Windows_1.0.0-beta13+16_Setup.exe',
        'browser_download_url': 'https://example.com/setup.exe',
        'size': 123,
      });

      expect(asset.type, ReleaseAssetType.windowsInstaller);
      expect(asset.platform, 'windows');
      expect(asset.supportsInAppInstall, isTrue);
      expect(asset.typeId, 'windows-installer');
    });

    test('detects portable assets', () {
      final windowsAsset = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_Windows_1.0.0_Portable.zip',
        'browser_download_url': 'https://example.com/windows.zip',
      });

      expect(windowsAsset.type, ReleaseAssetType.windowsPortable);
      expect(windowsAsset.supportsInAppInstall, isTrue);
      expect(windowsAsset.requiresManualReplace, isFalse);
      expect(windowsAsset.platform, 'windows');
    });

    test('detects the macOS app archive', () {
      final asset = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'WOF_NAI_Studio_macOS_2.1.0_Portable.zip',
        'browser_download_url': 'https://example.com/macos.zip',
        'size': 456,
      });

      expect(asset.type, ReleaseAssetType.macosPortable);
      expect(asset.platform, 'macos');
      expect(asset.typeId, 'macos-portable');
      expect(asset.supportsInAppInstall, isTrue);
      expect(asset.requiresManualReplace, isTrue);
    });

    test('does not treat the checksum sidecar as the macOS archive', () {
      final asset = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'WOF_NAI_Studio_macOS_2.1.0_Portable.zip.sha256',
        'browser_download_url': 'https://example.com/macos.zip.sha256',
      });

      expect(asset.type, ReleaseAssetType.unknown);
    });

    test('reads the macOS type from the release manifest', () {
      final asset = ReleaseAssetInfo.fromManifestAsset({
        'type': 'macos-portable',
        'fileName': 'WOF_NAI_Studio_macOS_2.1.0_Portable.zip',
        'downloadUrl': 'https://example.com/macos.zip',
        'sha256': 'abc123',
      });

      expect(ReleaseAssetInfo.parseType('macos-portable'), asset.type);
      expect(asset.type, ReleaseAssetType.macosPortable);
      expect(asset.platform, 'macos');
      expect(asset.sha256, 'abc123');
    });

    test('merges manifest metadata with GitHub asset', () {
      final githubAsset = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_Windows_1.0.0_Setup.exe',
        'browser_download_url': 'https://example.com/setup.exe',
        'size': 123,
      });
      final asset = ReleaseAssetInfo.fromManifestAsset({
        'type': 'windows-installer',
        'fileName': 'NAI_Launcher_Windows_1.0.0_Setup.exe',
        'sha256': 'abc123',
        'description': '安装版',
      }, githubAsset: githubAsset);

      expect(asset.downloadUrl, githubAsset.downloadUrl);
      expect(asset.size, 123);
      expect(asset.sha256, 'abc123');
      expect(asset.description, '安装版');
    });
  });
}
