/// Thumbnail generator -- the 1-to-1 port of React's `createThumbnail`
/// (src/features/private-dm/attachment-utils.ts L133-141). React's
/// `imageThumbnail` uses `createImageBitmap` + a canvas; this port uses the
/// pure-Dart `image` package (decode + copyResize + encodeJpg), so it works
/// on desktop + mobile + web with no native plugin. React's `videoThumbnail`
/// (a `<video>` seek + canvas draw) is ported to `media_kit`'s headless
/// `Player` + `screenshot()` -- see [_createVideoThumbnail].
//
// For non-image/non-video picks this returns null (mirrors React's non-image
// branch). A null thumbnail is never fatal -- React resolves undefined on
// any decode failure; the gateway treats a null `thumbnailBase64` as "no
// preview".
//
// Output: a base64-encoded JPEG (no `data:` prefix), matching React's
// `canvasToBase64` (`toDataURL("image/jpeg", 0.7)` then strip the prefix).
// The 320px max-edge + 70% quality mirror React's `THUMBNAIL_MAX_EDGE = 320`
// + the `0.7` quality arg. Aspect is preserved via `copyResize` (width-only
// resize auto-computes height, matching React's `scaledSize`).
library;

import 'dart:async' show Completer, StreamSubscription;
import 'dart:convert' show base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:image/image.dart' as img
    show decodeImage, decodeNamedImage, copyResize, encodeJpg;
import 'package:media_kit/media_kit.dart';
import 'package:mime/mime.dart' show lookupMimeType;

/// The max edge (px) for a thumbnail -- 1-в-1 with React `THUMBNAIL_MAX_EDGE`.
const int _thumbnailMaxEdge = 320;

/// JPEG quality (0-100) -- React's `0.7` (a 0-1 value) maps to 70 here.
const int _jpegQuality = 70;

/// Generates a base64-encoded JPEG thumbnail for an image or video file, or
/// null for other types / decode failures (mirrors React `createThumbnail`
/// returning `undefined` for non-media types and on any decode error).
///
/// [fileName] is used to infer the image decoder (via `decodeNamedImage`,
/// which keys off the extension). [bytes] is the raw file content (already
/// read by AttachmentPicker).
///
/// Image picks use the pure-Dart `image` package (no native plugin). Video
/// picks use `media_kit`'s headless `Player` + `screenshot()` -- the 1-to-1
/// port of React's `videoThumbnail` (seek to 10%, capture, re-encode). The
/// video branch is best-effort: if the media_kit native backend (libmpv) is
/// unavailable, it returns null rather than throwing (mirrors React's
/// `videoThumbnail` resolving `undefined` on any error). End-to-end video
/// capture is verified via integration_test, not `flutter test`.
Future<String?> createThumbnail(Uint8List bytes, String fileName) async {
  final mime = lookupMimeType(fileName) ?? '';
  if (mime.startsWith('image/')) {
    return _createImageThumbnail(bytes, fileName);
  }
  if (mime.startsWith('video/')) {
    return _createVideoThumbnail(bytes);
  }
  return null; // React: non-image/non-video => undefined
}

/// Image branch -- 1-to-1 with React `imageThumbnail`. Returns null for
/// non-images / decode failures (never fatal). Behavior-identical to the
/// pre-video-branch implementation (byte-identical output).
Future<String?> _createImageThumbnail(Uint8List bytes, String fileName) async {
  try {
    final decoded = img.decodeNamedImage(fileName, bytes);
    if (decoded == null) return null;
    // React scaledSize: scale = min(1, MAX / max(w, h, 1)); the longest edge
    // becomes MAX, the other scales by the same factor. copyResize with only
    // width set auto-computes height to preserve aspect -- so resize by the
    // LONGER dimension: width=MAX for landscape/square, height=MAX for
    // portrait (so the 320 edge is the portrait height).
    final w = decoded.width;
    final h = decoded.height;
    final resized = w >= h
        ? img.copyResize(decoded, width: _thumbnailMaxEdge)
        : img.copyResize(decoded, height: _thumbnailMaxEdge);
    final jpeg = img.encodeJpg(resized, quality: _jpegQuality);
    return base64Encode(jpeg);
  } on Exception {
    return null; // never fatal -- mirrors React's try/catch -> undefined
  }
}

/// Video branch -- 1-to-1 with React `videoThumbnail`. Seeks to 10% of the
/// duration, captures a frame via `media_kit`'s headless `Player.screenshot()`,
/// then decodes + resizes to 320px max-edge + re-encodes JPEG q70 (the same
/// output shape as the image branch, matching React's `scaledSize` + `0.7`).
///
/// Best-effort: returns null on ANY failure. The media_kit native backend
/// (libmpv-2.dll) is a `flutter build windows` artifact and is absent from the
/// `flutter test` isolate, so this resolves null there (the defensive
/// contract). A real mp4 capture is exercised via integration_test.
Future<String?> _createVideoThumbnail(Uint8List bytes) async {
  Player? player;
  StreamSubscription<Duration>? durSub;
  StreamSubscription<Duration>? posSub;
  try {
    // vo stays default 'null' (headless) -- do NOT set vo.
    player = Player(configuration: const PlayerConfiguration(muted: true));
    final media = await Media.memory(bytes);
    await player.open(media, play: false);

    // 1) Wait for duration (>0). React's 6s overall budget; 4s here per the
    //    tracer-bullet await sequence. Fall back to 2s on timeout so the
    //    seek still runs against a sane target.
    final durCompleter = Completer<Duration>();
    durSub = player.stream.duration.listen((d) {
      if (d > Duration.zero && !durCompleter.isCompleted) {
        durCompleter.complete(d);
      }
    });
    if (player.state.duration > Duration.zero && !durCompleter.isCompleted) {
      durCompleter.complete(player.state.duration);
    }
    final duration = await durCompleter.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => const Duration(seconds: 2),
    );
    await durSub.cancel();
    durSub = null;

    // 2) Seek to 10% (clamped to [0,1000]ms, mirroring React's `Math.min(1,
    //    duration * 0.1)`). seek() resolves on command issue, not frame
    //    render, so wait for the position stream to reach the target.
    final target = Duration(
      milliseconds: (duration.inMilliseconds * 0.1).round().clamp(0, 1000),
    );
    final seekCompleter = Completer<void>();
    posSub = player.stream.position.listen((p) {
      if ((p - target).inMilliseconds.abs() < 250 &&
          !seekCompleter.isCompleted) {
        seekCompleter.complete();
      }
    });
    await player.seek(target);
    await seekCompleter.future
        .timeout(const Duration(seconds: 4), onTimeout: () {});
    await posSub.cancel();
    posSub = null;
    // Let the frame render before the screenshot.
    await Future<void>.delayed(const Duration(milliseconds: 120));

    // 3) Capture (default 'image/jpeg'). May be null if no frame decoded;
    //    retry once after a short wait.
    Uint8List? frame = await player.screenshot();
    frame ??= await player
        .screenshot()
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
    if (frame == null || frame.isEmpty) return null;

    // 4) Decode + resize to 320px max-edge + re-encode JPEG q70 (React parity
    //    with the image branch). decodeImage sniffs the format from the JPEG
    //    bytes returned by screenshot().
    final decoded = img.decodeImage(frame);
    if (decoded == null) return null;
    final w = decoded.width;
    final h = decoded.height;
    final resized = w >= h
        ? img.copyResize(decoded, width: _thumbnailMaxEdge)
        : img.copyResize(decoded, height: _thumbnailMaxEdge);
    final jpeg = img.encodeJpg(resized, quality: _jpegQuality);
    return base64Encode(jpeg);
  } on Exception {
    // media_kit native backend unavailable / decode failure -- never fatal.
    return null;
  } finally {
    // Player owns a libmpv handle + isolate; MUST be disposed. Cancel any
    // outstanding stream subs too (the listener Completers may be dangling).
    await posSub?.cancel();
    await durSub?.cancel();
    await player?.dispose();
  }
}
