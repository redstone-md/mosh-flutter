import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/features/conversation/attachment_preview_image.dart';

void main() {
  test('JPEG and PNG headers reveal dimensions without decoding', () {
    final jpeg = img.encodeJpg(img.Image(width: 48, height: 32));
    final png = img.encodePng(img.Image(width: 24, height: 40));
    expect(encodedImageSize(jpeg), const Size(48, 32));
    expect(encodedImageSize(png), const Size(24, 40));
    // Fill bytes may precede any marker.
    final padded = Uint8List.fromList([...jpeg.take(2), 0xFF, ...jpeg.skip(2)]);
    expect(encodedImageSize(padded), const Size(48, 32));
  });

  test('truncated, unknown or empty images reveal no size', () {
    final jpeg = img.encodeJpg(img.Image(width: 48, height: 32));
    expect(encodedImageSize(Uint8List(0)), isNull);
    expect(encodedImageSize(Uint8List.fromList([1, 2, 3, 4])), isNull);
    expect(encodedImageSize(Uint8List.sublistView(jpeg, 0, 30)), isNull);
    expect(encodedImageSize(img.encodeGif(img.Image(width: 4, height: 4))),
        isNull);
    final empty = img.encodePng(img.Image(width: 1, height: 1))
      ..setRange(16, 24, List.filled(8, 0));
    expect(encodedImageSize(empty), isNull);
  });

  test('preview height follows the aspect ratio within its bounds', () {
    expect(attachmentPreviewHeight(const Size(300, 200)), closeTo(213.3, 0.1));
    expect(attachmentPreviewHeight(const Size(10, 100)),
        kAttachmentPreviewMaxHeight);
    expect(attachmentPreviewHeight(const Size(100, 1)),
        kAttachmentPreviewMinHeight);
    expect(attachmentPreviewHeight(null), kAttachmentPreviewFallbackHeight);
  });
}
