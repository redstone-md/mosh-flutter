// A video's previews on Android: the frame comes from the system's decoder,
// which reads the video from a file the app removes afterwards.
import 'dart:convert' show base64Decode;
import 'dart:io' show File;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/src/features/shared/thumbnail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mosh/video-frame');
  final video = Uint8List.fromList(List.generate(64, (index) => index));
  late String path;
  late List<int> handed;

  /// The decoder answers every video with [frame], or fails without one.
  void decoder(Uint8List? frame) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      path = call.arguments as String;
      handed = File(path).readAsBytesSync();
      if (frame == null) throw PlatformException(code: 'video-frame');
      return frame;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  test('the previews are made from the frame the system takes', () async {
    decoder(img.encodeJpg(img.Image(width: 640, height: 480)));

    final previews = await createAttachmentPreviews(video, 'clip.mp4',
        videoFrame: systemVideoFrame);

    expect(handed, video);
    expect(File(path).existsSync(), isFalse);
    final preview = img.decodeJpg(base64Decode(previews!.previewBase64))!;
    expect((preview.width, preview.height), (320, 240));
  });

  test('a video the system takes no frame of has no previews', () async {
    decoder(null);

    final previews = await createAttachmentPreviews(video, 'clip.mp4',
        videoFrame: systemVideoFrame);

    expect(previews, isNull);
    expect(File(path).existsSync(), isFalse);
  });
}
