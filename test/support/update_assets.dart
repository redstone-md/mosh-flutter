// Scripted release assets for the update tests: deterministic bytes, a real
// SHA-256 over them, and an opener that serves them without a socket.
import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:mosh/src/features/settings/app_release_provider.dart';
import 'package:mosh/src/features/settings/app_update_download.dart';

/// Deterministic bytes, so a checksum is stable across runs.
List<int> updateBytes(int length) =>
    List<int>.generate(length, (index) => index % 251);

String hexOf(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Future<String> sha256Of(List<int> bytes) async =>
    hexOf((await Sha256().hash(bytes)).bytes);

/// A release carrying [assetNames] as its uploaded files.
PublishedRelease releaseWithAssets({
  String version = '0.22.0',
  List<String> assetNames = const [
    'mosh-0.22.0-setup.exe',
    'mosh-0.22.0-setup.exe.sha256',
  ],
}) =>
    PublishedRelease(
      version: version,
      pageUri: Uri.parse('https://example.test/releases/$version'),
      assets: [
        for (final name in assetNames)
          ReleaseAsset(
            name: name,
            downloadUri: Uri.parse('https://example.test/assets/$name'),
          ),
      ],
    );

/// Serves asset bodies to the downloader's own seam, so a test drives the real
/// download, its progress reporting and its verification with no network.
class ScriptedAssets {
  ScriptedAssets(
    this.bodies, {
    this.failures = const {},
    this.held = const {},
    this.sizes = const {},
  });

  final Map<String, List<int>> bodies;

  /// Paths that answer with an error instead of a body.
  final Map<String, Object> failures;

  /// Paths whose bodies arrive through a controller the test feeds, which is
  /// how a download that dies mid-flight is written.
  final Set<String> held;

  /// Paths whose declared size the opener withholds.
  final Set<String> sizes;

  final List<Uri> asked = [];
  final List<StreamController<List<int>>> open = [];

  Future<AssetStream> openUrl(Uri url) async {
    asked.add(url);
    final path = url.path;
    final failure = failures[path];
    if (failure != null) throw failure;
    final body = bodies[path];
    if (body == null) throw StateError('no scripted body for $url');
    final length = sizes.contains(path) ? null : body.length;
    if (!held.contains(path)) {
      return AssetStream(
        bytes: Stream<List<int>>.fromIterable(<List<int>>[body]),
        length: length,
        dispose: () {},
      );
    }
    final controller = StreamController<List<int>>();
    open.add(controller);
    return AssetStream(
      bytes: controller.stream,
      length: length,
      dispose: () {},
    );
  }
}
