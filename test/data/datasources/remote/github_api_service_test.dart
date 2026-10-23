import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/datasources/remote/github_api_service.dart';
import 'package:nai_launcher/data/models/version/release_asset_info.dart';

/// 用固定的 Release 数据代替 GitHub，不发真实请求。
class _ReleaseAdapter implements HttpClientAdapter {
  _ReleaseAdapter(this.routes);

  final Map<String, Object> routes;
  final requested = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requested.add(url);
    final body = routes[url];
    if (body == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _base = 'https://api.example.test';
const _download = 'https://example.test/download';

Map<String, Object> _githubAsset(String name, int size) => {
  'name': name,
  'browser_download_url': '$_download/$name',
  'size': size,
};

Map<String, Object> _release(List<Map<String, Object>> assets) => {
  'tag_name': 'v2.1.0',
  'name': 'W.O.F NAI Studio v2.1.0',
  'body': 'notes',
  'published_at': '2026-10-30T00:00:00Z',
  'html_url': 'https://example.test/releases/v2.1.0',
  'assets': assets,
};

GitHubApiService _service(_ReleaseAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: _base))..httpClientAdapter = adapter;
  return GitHubApiService(dio: dio);
}

void main() {
  const setup = 'WOF_NAI_Studio_Windows_2.1.0_Setup.exe';
  const portable = 'WOF_NAI_Studio_Windows_2.1.0_Portable.zip';
  const mac = 'WOF_NAI_Studio_macOS_2.1.0_Portable.zip';

  // Release 里的上传顺序：校验文件夹在安装包之间，清单最后上传。
  final fullRelease = _release([
    _githubAsset('$mac.sha256', 96),
    _githubAsset(mac, 300),
    _githubAsset('$portable.sha256', 96),
    _githubAsset(portable, 200),
    _githubAsset(setup, 100),
    _githubAsset('checksums.txt', 300),
    _githubAsset('release_manifest.json', 1000),
  ]);
  final manifest = {
    'version': '2.1.0+43',
    'tag': 'v2.1.0',
    'assets': [
      {
        'platform': 'macos',
        'type': 'macos-portable',
        'fileName': mac,
        'downloadUrl': '$_download/$mac',
        'sha256': 'mac-sha',
        'size': 300,
      },
      {
        'platform': 'windows',
        'type': 'windows-installer',
        'fileName': setup,
        'downloadUrl': '$_download/$setup',
        'sha256': 'setup-sha',
        'size': 100,
      },
      {
        'platform': 'windows',
        'type': 'windows-portable',
        'fileName': portable,
        'downloadUrl': '$_download/$portable',
        'sha256': 'portable-sha',
        'size': 200,
      },
    ],
  };
  final routes = <String, Object>{
    '$_base/repos/owner/repo/releases/latest': fullRelease,
    '$_download/release_manifest.json': manifest,
  };

  test('macOS picks the app archive with its manifest checksum', () async {
    final info = await _service(_ReleaseAdapter(routes)).fetchLatestRelease(
      owner: 'owner',
      repo: 'repo',
      currentVersion: '2.0.0',
      platform: 'macos',
    );

    expect(info.isNewer, isTrue);
    expect(info.primaryAsset?.type, ReleaseAssetType.macosPortable);
    expect(info.primaryAsset?.fileName, mac);
    expect(info.primaryAsset?.sha256, 'mac-sha');
    expect(info.downloadUrl, '$_download/$mac');
    expect(info.supportsInAppInstall, isTrue);
  });

  test('macOS without a manifest still skips the checksum sidecar', () async {
    final info =
        await _service(
          _ReleaseAdapter({
            '$_base/repos/owner/repo/releases/latest': _release([
              _githubAsset('$mac.sha256', 96),
              _githubAsset(mac, 300),
              _githubAsset(setup, 100),
            ]),
          }),
        ).fetchLatestRelease(
          owner: 'owner',
          repo: 'repo',
          currentVersion: '2.0.0',
          platform: 'macos',
        );

    expect(info.primaryAsset?.fileName, mac);
    // 没有清单就没有 SHA256，只能去 Release 页面手动下载。
    expect(info.supportsInAppInstall, isFalse);
  });

  test(
    'macOS never falls back to a Windows package when the release has no Mac build',
    () async {
      final info =
          await _service(
            _ReleaseAdapter({
              '$_base/repos/owner/repo/releases/latest': _release([
                _githubAsset(setup, 100),
                _githubAsset(portable, 200),
              ]),
            }),
          ).fetchLatestRelease(
            owner: 'owner',
            repo: 'repo',
            currentVersion: '2.0.0',
            platform: 'macos',
          );

      expect(info.primaryAsset, isNull);
      expect(info.downloadUrl, 'https://example.test/releases/v2.1.0');
      expect(info.supportsInAppInstall, isFalse);
    },
  );

  test('Windows keeps choosing its own packages next to a Mac build', () async {
    final service = _service(_ReleaseAdapter(routes));

    final installer = await service.fetchLatestRelease(
      owner: 'owner',
      repo: 'repo',
      currentVersion: '2.0.0',
      platform: 'windows-installer',
    );
    final portableInfo = await service.fetchLatestRelease(
      owner: 'owner',
      repo: 'repo',
      currentVersion: '2.0.0',
      platform: 'windows-portable',
    );

    expect(installer.primaryAsset?.fileName, setup);
    expect(installer.primaryAsset?.sha256, 'setup-sha');
    expect(portableInfo.primaryAsset?.fileName, portable);
    expect(portableInfo.primaryAsset?.sha256, 'portable-sha');
  });
}
