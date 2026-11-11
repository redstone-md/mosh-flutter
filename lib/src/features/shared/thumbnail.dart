import 'dart:async' show Completer, StreamSubscription;
import 'dart:io' show Directory, File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:image/image.dart' as img show decodeImage, decodeNamedImage;
import 'package:media_kit/media_kit.dart';
import 'package:mime/mime.dart' show lookupMimeType;

import 'image_previews.dart';
import 'media_player.dart' show playsThroughSystem;

/// Takes one frame of a video as an encoded image; null when it has none.
typedef VideoFrame = Future<Uint8List?> Function(Uint8List video);

/// Generates a base64-encoded JPEG thumbnail for an image or video file, or
/// null for other types / decode failures.
///
/// [fileName] is used to infer the image decoder (via `decodeNamedImage`,
/// which keys off the extension). [bytes] is the raw file content (already
/// read by AttachmentPicker).
///
/// Image picks use the pure-Dart `image` package (no native plugin). Video
/// picks take one frame, a tenth into the video, and encode it the same
/// way: with a headless libmpv player ([playerVideoFrame]), or on Android
/// with the system's decoder ([systemVideoFrame]). The video branch is
/// best-effort: a video that gives no frame has no thumbnail. End-to-end
/// capture is verified with real libmpv in the native media tests.
Future<String?> createThumbnail(Uint8List bytes, String fileName) async {
  return (await createAttachmentPreviews(bytes, fileName))?.previewBase64;
}

/// Decode once and generate both the inline miniature and the clear preview.
/// [videoFrame] is how a video's frame is taken; the platform's by default.
Future<AttachmentPreviews?> createAttachmentPreviews(
    Uint8List bytes, String fileName,
    {VideoFrame? videoFrame}) async {
  final mime = lookupMimeType(fileName) ?? '';
  if (mime.startsWith('image/')) {
    return _createImageThumbnail(bytes, fileName);
  }
  if (mime.startsWith('video/')) {
    final take = videoFrame ??
        (playsThroughSystem ? systemVideoFrame : playerVideoFrame);
    final frame = await take(bytes);
    if (frame == null || frame.isEmpty) return null;
    // Decoded, resized and encoded off the main isolate, as an image is.
    return compute(_decodeVideoFrame, frame,
        debugLabel: 'video-attachment-previews');
  }
  return null; // non-image/non-video => no thumbnail
}

/// Image branch. Returns null for
/// non-images / decode failures (never fatal).
Future<AttachmentPreviews?> _createImageThumbnail(
        Uint8List bytes, String fileName) =>
    compute(_decodeImagePreviews, (bytes, fileName),
        debugLabel: 'attachment-previews');

AttachmentPreviews? _decodeVideoFrame(Uint8List frame) {
  try {
    final decoded = img.decodeImage(frame);
    if (decoded == null) return null;
    return encodeImagePreviews(decoded);
  } catch (_) {
    // Never fatal -- resolve null on any decode/encode failure. `catch (_)` on
    // purpose: a corrupt frame can throw a RangeError (an Error, not an
    // Exception), matching the same guard used in _decodeImagePreviews.
    return null;
  }
}

AttachmentPreviews? _decodeImagePreviews((Uint8List, String) input) {
  final (bytes, fileName) = input;
  try {
    final decoded = img.decodeNamedImage(fileName, bytes, frame: 0) ??
        img.decodeImage(bytes, frame: 0);
    if (decoded == null) return null;
    return encodeImagePreviews(decoded, original: bytes);
  } catch (_) {
    // Never fatal -- resolve null on any decode failure. `catch (_)` on
    // purpose: a corrupt or oversized bitmap throws a RangeError, an Error,
    // not an Exception, and that used to escape as an uncaught async error.
    return null;
  }
}

const _systemFrames = MethodChannel('mosh/video-frame');

/// A frame of [video] from Android's own decoder, as a JPEG. The decoder
/// reads a file, so the video stays in the app's cache for the call.
Future<Uint8List?> systemVideoFrame(Uint8List video) async {
  Directory? directory;
  try {
    directory = await Directory.systemTemp.createTemp('mosh-frame');
    final file = File('${directory.path}/video');
    await file.writeAsBytes(video);
    return await _systemFrames.invokeMethod<Uint8List>('take', file.path);
  } on Exception {
    // No decoder for this video, or no room for the file: never fatal.
    return null;
  } finally {
    await directory?.delete(recursive: true);
  }
}

/// A frame of [video] from a headless libmpv player: it seeks a tenth in
/// and takes a screenshot. Null where libmpv is unavailable or gives no
/// frame. A headless player must enable its video track itself, because
/// media_kit otherwise waits for a VideoController to enable decoding.
Future<Uint8List?> playerVideoFrame(Uint8List bytes) async {
  Player? player;
  StreamSubscription<Duration>? durSub;
  StreamSubscription<Duration>? posSub;
  try {
    // vo stays default 'null' (headless) -- do NOT set vo.
    player = Player(configuration: const PlayerConfiguration(muted: true));
    await player.setVideoTrack(VideoTrack.auto());
    final media = await Media.memory(bytes);
    await player.open(media, play: false);

    // 1) Wait for duration (>0). 4s budget per the
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

    // 2) Seek to 10% (clamped to [0,1000]ms). seek() resolves on command
    //    issue, not frame
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
    return frame;
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
