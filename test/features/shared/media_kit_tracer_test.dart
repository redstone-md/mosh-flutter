// Native capture uses real libmpv and the committed sample.mp4 fixture.
// Headless players must enable VideoTrack.auto(): without a VideoController,
// media_kit defaults to vid=no and produces no decoded frame.
// This test verifies the app's bounded attachment previews;
// only hosts without the native backend skip them.
import 'dart:convert' show base64Decode;
import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:mosh/src/features/shared/thumbnail.dart';

void main() {
  // `flutter test` never runs lib/main.dart, so MediaKit's native libs are
  // not registered in the test isolate by default. Probe init up front; if
  // the native backend is missing we skip the probe (do not fail the suite).
  String? skipReason;
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    skipReason = 'media_kit native backend unavailable in `flutter test`: $e. '
        'Install or stage libmpv to run native capture tests.';
  }

  test('video attachment generates a miniature and a clear preview', () async {
    final fixture = File('test/fixtures/sample.mp4');
    expect(fixture.existsSync(), isTrue);
    final previews =
        await createAttachmentPreviews(fixture.readAsBytesSync(), 'sample.mp4');
    expect(previews, isNotNull);
    final miniature = base64Decode(previews!.miniatureBase64);
    final clear = base64Decode(previews.previewBase64);
    expect(previews.miniatureBase64.length, lessThanOrEqualTo(2048));
    expect(img.decodeJpg(miniature), isNotNull);
    final decoded = img.decodeJpg(clear)!;
    expect(decoded.width, 320);
    expect(decoded.height, 240);
  }, skip: skipReason, timeout: const Timeout(Duration(seconds: 30)));
}
