import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/settings/app_release_provider.dart';
import 'package:mosh/src/features/settings/app_update_apply.dart';
import 'package:mosh/src/features/settings/app_update_install.dart';

import '../../support/update_assets.dart';

void main() {
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

  test('a sandboxed macOS build installs nothing by itself', () {
    final container = ProviderContainer(overrides: [
      hostPlatformProvider.overrideWithValue(HostPlatform.macOS),
    ]);
    addTearDown(container.dispose);

    expect(container.read(updateApplierProvider).supported, isFalse);
  });
}
