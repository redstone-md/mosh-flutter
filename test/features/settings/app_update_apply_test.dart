import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/settings/app_release_provider.dart';
import 'package:mosh/src/features/settings/app_update_apply.dart';

import '../../support/update_assets.dart';

/// Shims for the macOS commands the swap script calls, so the real script is
/// driven end to end on any host with bash.
Directory _shims(Directory root, {bool dittoFails = false}) {
  final shims = Directory('${root.path}/shims')..createSync(recursive: true);
  final log = File('${root.path}/shim.log');

  void shim(String name, String body) {
    final file = File('${shims.path}/$name')
      ..writeAsStringSync('#!/bin/bash\n$body\n');
    Process.runSync('chmod', ['+x', file.path]);
  }

  shim('hdiutil', '''
if [ "\$1" = "attach" ]; then
  mount=""
  while [ \$# -gt 0 ]; do
    if [ "\$1" = "-mountpoint" ]; then mount="\$2"; shift; fi
    shift
  done
  mkdir -p "\$mount/Mosh.app/Contents"
  echo new > "\$mount/Mosh.app/Contents/marker"
  exit 0
fi
exit 0
''');
  shim('ditto', '''
echo "ditto \$1 \$2" >> "${log.path}"
${dittoFails ? 'exit 1' : 'cp -R "\$1" "\$2"'}
''');
  shim('open', 'echo "open \$1" >> "${log.path}"');
  return shims;
}

void main() {
  final hasBash = File('/bin/bash').existsSync();

  group('updateCandidateFor', () {
    test('a windows install takes the installer and its sidecar', () {
      final candidate =
          updateCandidateFor(releaseWithAssets(), HostPlatform.windows);
      expect(candidate?.artifact.name, 'mosh-0.22.0-setup.exe');
      expect(candidate?.checksum.name, 'mosh-0.22.0-setup.exe.sha256');
    });

    test('a mac install takes the image of this release', () {
      final candidate = updateCandidateFor(
        releaseWithAssets(assetNames: const [
          'Mosh_0.22.0_universal.dmg',
          'Mosh_0.22.0_universal.dmg.sha256',
        ]),
        HostPlatform.macOS,
      );
      expect(candidate?.artifact.name, 'Mosh_0.22.0_universal.dmg');
    });

    test('an artifact without a published sidecar is not installed', () {
      expect(
        updateCandidateFor(
          releaseWithAssets(assetNames: const ['mosh-0.22.0-setup.exe']),
          HostPlatform.windows,
        ),
        isNull,
      );
    });

    test('another version in the release is not this release', () {
      expect(
        updateCandidateFor(
          releaseWithAssets(assetNames: const [
            'mosh-0.21.0-setup.exe',
            'mosh-0.21.0-setup.exe.sha256',
          ]),
          HostPlatform.windows,
        ),
        isNull,
      );
    });

    test('a host with no published artifacts installs nothing', () {
      expect(
          updateCandidateFor(releaseWithAssets(), HostPlatform.other), isNull);
      expect(const UnsupportedUpdateApplier().supported, isFalse);
    });
  });

  test('windows hands the installer its silent flags and ends the app',
      () async {
    final calls = <({
      String executable,
      List<String> arguments,
      ProcessStartMode mode
    })>[];
    final terminated = <int>[];
    final applier = WindowsUpdateApplier(
      start: (executable, arguments, mode) async =>
          calls.add((executable: executable, arguments: arguments, mode: mode)),
      terminate: terminated.add,
    );

    await applier.apply(File('/updates/mosh-0.22.0-setup.exe'));

    expect(calls.single.executable, '/updates/mosh-0.22.0-setup.exe');
    expect(calls.single.arguments,
        <String>['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/RELAUNCH=1']);
    expect(calls.single.mode, ProcessStartMode.detached);
    expect(terminated, [0]);
    expect(applier.supported, isTrue);
  });

  test('the mac bundle is found from the running executable', () {
    expect(
      MacOsUpdateApplier.bundlePath(
          '/Applications/Mosh.app/Contents/MacOS/mosh'),
      '/Applications/Mosh.app',
    );
  });

  test('mac swaps the bundle through a script that outlives the app', () async {
    final staging = Directory.systemTemp.createTempSync('mosh-swap');
    addTearDown(() => staging.deleteSync(recursive: true));
    final artifact = File('${staging.path}/Mosh_0.22.0_universal.dmg')
      ..writeAsStringSync('image');
    final calls = <({
      String executable,
      List<String> arguments,
      ProcessStartMode mode
    })>[];
    final terminated = <int>[];
    final applier = MacOsUpdateApplier(
      executable: '/Applications/Mosh.app/Contents/MacOS/mosh',
      processId: () => 4242,
      start: (executable, arguments, mode) async =>
          calls.add((executable: executable, arguments: arguments, mode: mode)),
      terminate: terminated.add,
    );

    await applier.apply(artifact);

    final script = File('${staging.path}/mosh-swap.sh');
    expect(script.existsSync(), isTrue);
    expect(calls.single.executable, '/bin/bash');
    expect(calls.single.arguments, <String>[
      script.path,
      '4242',
      artifact.path,
      '/Applications/Mosh.app',
    ]);
    expect(calls.single.mode, ProcessStartMode.detached);
    expect(terminated, [0]);
  });

  group('the swap script', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('mosh-swap-run'));
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    /// Runs the real script with the shims first on PATH and a finished pid, so
    /// the wait loop returns immediately.
    ProcessResult run(Directory shims, Directory staging, String image) {
      final script = File('${staging.path}/mosh-swap.sh')
        ..writeAsStringSync(MacOsUpdateApplier.swapScript);
      final dead = Process.runSync('true', const []);
      return Process.runSync(
        '/bin/bash',
        [script.path, '${dead.pid}', image, '${staging.path}/Mosh.app'],
        environment: {'PATH': '${shims.path}:${Platform.environment['PATH']}'},
      );
    }

    test('replaces the bundle and starts the new one', () {
      final staging = Directory('${root.path}/Applications')..createSync();
      Directory('${staging.path}/Mosh.app/Contents')
          .createSync(recursive: true);
      File('${staging.path}/Mosh.app/Contents/marker').writeAsStringSync('old');
      final image = File('${staging.path}/update.dmg')..writeAsStringSync('x');
      final shims = _shims(root);

      final result = run(shims, staging, image.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        File('${staging.path}/Mosh.app/Contents/marker')
            .readAsStringSync()
            .trim(),
        'new',
      );
      expect(Directory('${staging.path}/Mosh.app.old').existsSync(), isFalse);
      expect(File('${root.path}/shim.log').readAsStringSync(),
          contains('open ${staging.path}/Mosh.app'));
      expect(image.existsSync(), isFalse);
    }, skip: hasBash ? null : 'bash is unavailable');

    test('puts the previous bundle back when the copy fails', () {
      final staging = Directory('${root.path}/Applications')..createSync();
      Directory('${staging.path}/Mosh.app/Contents')
          .createSync(recursive: true);
      File('${staging.path}/Mosh.app/Contents/marker').writeAsStringSync('old');
      final image = File('${staging.path}/update.dmg')..writeAsStringSync('x');
      final shims = _shims(root, dittoFails: true);

      final result = run(shims, staging, image.path);

      expect(result.exitCode, isNot(0));
      expect(
        File('${staging.path}/Mosh.app/Contents/marker').readAsStringSync(),
        'old',
      );
      expect(File('${root.path}/shim.log').readAsStringSync(),
          contains('open ${staging.path}/Mosh.app'));
    }, skip: hasBash ? null : 'bash is unavailable');
  });
}
