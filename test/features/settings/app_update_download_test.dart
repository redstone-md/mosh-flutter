import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/settings/app_release_provider.dart';
import 'package:mosh/src/features/settings/app_update_download.dart';

import '../../support/update_assets.dart';

void main() {
  late Directory staging;

  setUp(() => staging = Directory.systemTemp.createTempSync('mosh-update'));
  tearDown(() {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  });

  ReleaseDownloader downloaderFor(ScriptedAssets assets) => ReleaseDownloader(
        open: assets.openUrl,
        staging: () async => staging,
      );

  UpdateCandidate windowsCandidate() {
    final candidate =
        updateCandidateFor(releaseWithAssets(), HostPlatform.windows);
    expect(candidate, isNotNull);
    return candidate!;
  }

  test('a verified artifact lands in staging and reports its progress',
      () async {
    final bytes = updateBytes(4096);
    final digest = await sha256Of(bytes);
    final assets = ScriptedAssets({
      '/assets/mosh-0.22.0-setup.exe': bytes,
      '/assets/mosh-0.22.0-setup.exe.sha256':
          utf8.encode('$digest  mosh-0.22.0-setup.exe\n'),
    });
    final progress = <(int, int?)>[];

    final file = await downloaderFor(assets).download(
      windowsCandidate(),
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(file.readAsBytesSync(), bytes);
    expect(progress, [(4096, 4096)]);
    // The published sidecar is read before the artifact it describes.
    expect(assets.asked.map((uri) => uri.path).toList(), [
      '/assets/mosh-0.22.0-setup.exe.sha256',
      '/assets/mosh-0.22.0-setup.exe',
    ]);
  });

  test('a download with no declared size still reports what arrived', () async {
    final bytes = updateBytes(512);
    final digest = await sha256Of(bytes);
    final assets = ScriptedAssets({
      '/assets/mosh-0.22.0-setup.exe': bytes,
      '/assets/mosh-0.22.0-setup.exe.sha256':
          utf8.encode('$digest  mosh-0.22.0-setup.exe'),
    }, sizes: {
      '/assets/mosh-0.22.0-setup.exe'
    });
    final progress = <(int, int?)>[];

    await downloaderFor(assets).download(
      windowsCandidate(),
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(progress, [(512, null)]);
  });

  test('a checksum mismatch is refused and nothing is left behind', () async {
    final assets = ScriptedAssets({
      '/assets/mosh-0.22.0-setup.exe': updateBytes(128),
      '/assets/mosh-0.22.0-setup.exe.sha256':
          utf8.encode('${'0' * 64}  mosh-0.22.0-setup.exe\n'),
    });

    await expectLater(downloaderFor(assets).download(windowsCandidate()),
        throwsA(isA<UpdateDownloadException>()));

    expect(staging.listSync(), isEmpty);
  });

  test('a download that dies mid-flight leaves nothing behind', () async {
    final bytes = updateBytes(256);
    final digest = await sha256Of(bytes);
    final assets = ScriptedAssets({
      '/assets/mosh-0.22.0-setup.exe': bytes,
      '/assets/mosh-0.22.0-setup.exe.sha256':
          utf8.encode('$digest  mosh-0.22.0-setup.exe'),
    }, held: {
      '/assets/mosh-0.22.0-setup.exe'
    });

    final download = downloaderFor(assets).download(windowsCandidate());
    await pumpEventQueue();
    final body = assets.open.single;
    body.add(bytes.sublist(0, 64));
    body.addError(const SocketException('connection lost'));
    await body.close();

    await expectLater(download, throwsA(isA<SocketException>()));
    expect(staging.listSync(), isEmpty);
  });

  test('a release without a usable checksum is not downloaded at all',
      () async {
    final assets = ScriptedAssets({
      '/assets/mosh-0.22.0-setup.exe.sha256': utf8.encode('not a checksum'),
      '/assets/mosh-0.22.0-setup.exe': updateBytes(64),
    });

    await expectLater(downloaderFor(assets).download(windowsCandidate()),
        throwsA(isA<UpdateDownloadException>()));

    expect(assets.asked, hasLength(1));
    expect(staging.listSync(), isEmpty);
  });

  group('parseSha256Sidecar', () {
    test('reads the published digest and tolerates a missing name', () {
      final digest = 'a' * 64;
      expect(
          parseSha256Sidecar(
              '$digest  mosh-0.22.0-setup.exe\n', 'mosh-0.22.0-setup.exe'),
          digest);
      expect(parseSha256Sidecar('$digest\n', 'mosh-0.22.0-setup.exe'), digest);
      expect(parseSha256Sidecar('${'A' * 64}\n', 'mosh-0.22.0-setup.exe'),
          'a' * 64);
    });

    test('refuses a digest for another file, or no digest at all', () {
      expect(
          () => parseSha256Sidecar(
              '${'a' * 64}  other.exe\n', 'mosh-0.22.0-setup.exe'),
          throwsA(isA<UpdateDownloadException>()));
      expect(() => parseSha256Sidecar('', 'mosh-0.22.0-setup.exe'),
          throwsA(isA<UpdateDownloadException>()));
      expect(() => parseSha256Sidecar('${'a' * 63}\n', 'x'),
          throwsA(isA<UpdateDownloadException>()));
    });
  });
}
