import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/rag/rag_platform.dart';
import 'package:nai_launcher/core/rag/rag_runtime.dart';
import 'package:nai_launcher/core/rag/rag_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  test('the host is read from the machine running the tests', () {
    expect(RagPlatform.host == RagPlatform.windows, Platform.isWindows);
    expect(RagPlatform.host.isMacOS, Platform.isMacOS);
  });

  test('managed interpreters follow the uv venv layout of each system', () {
    final root = p.join('data', 'rag', 'v1');
    expect(
      RagPlatform.windows.managedPython(root),
      p.join(root, 'runtime', 'Scripts', 'python.exe'),
    );
    for (final mac in [RagPlatform.macOSArm64, RagPlatform.macOSX64]) {
      expect(mac.isMacOS, isTrue);
      expect(
        mac.managedPython(root),
        p.join(root, 'runtime', 'bin', 'python3'),
      );
    }
  });

  test('only Windows offers CUDA; a Mac sends a saved cuda as auto', () {
    expect(RagPlatform.windows.supportsCuda, isTrue);
    expect(RagPlatform.macOSArm64.supportsCuda, isFalse);
    expect(RagPlatform.macOSX64.supportsCuda, isFalse);
    const cuda = RagSettings(device: RagDevice.cuda);
    expect(cuda.deviceOn(RagPlatform.windows), RagDevice.cuda);
    expect(cuda.deviceOn(RagPlatform.macOSArm64), RagDevice.auto);
    for (final device in [RagDevice.auto, RagDevice.cpu]) {
      expect(
        RagSettings(device: device).deviceOn(RagPlatform.macOSArm64),
        device,
      );
    }
  });

  test('uv is pinned per platform; Intel Macs have no runtime', () {
    final windows = RagRuntimeInstaller.uvFor(RagPlatform.windows)!;
    expect(
      windows.url,
      'https://github.com/astral-sh/uv/releases/download/0.13.1/uv-x86_64-pc-windows-msvc.zip',
    );
    expect(
      windows.sha256,
      '3b2661a463a5baea7f5076ea2b25ab71d77f36a6c0d809e5350651792f80a672',
    );
    expect((windows.entry, windows.file), ('uv.exe', 'uv-0.13.1.exe'));
    final mac = RagRuntimeInstaller.uvFor(RagPlatform.macOSArm64)!;
    expect(
      mac.url,
      'https://github.com/astral-sh/uv/releases/download/0.13.1/uv-aarch64-apple-darwin.tar.gz',
    );
    expect(
      mac.sha256,
      'cfe454573412ff7380d15fc7dae5997ab53ffce72fce0a78e91ddbc84001acd2',
    );
    expect((mac.entry, mac.file), ('uv', 'uv-0.13.1'));
    expect(RagRuntimeInstaller.uvFor(RagPlatform.macOSX64), isNull);
    expect(RagRuntimeInstaller.uvFor(RagPlatform.other), isNull);
  });
}
