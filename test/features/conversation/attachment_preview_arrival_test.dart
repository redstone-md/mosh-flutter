import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';

import '../../support/pump.dart';

final _miniature =
    base64Encode(img.encodePng(img.Image(width: 24, height: 16)));

AttachmentDescriptor _descriptor() => AttachmentDescriptor(
      attachmentId: 'photo',
      contentHash: 'hash',
      fileName: 'photo.png',
      mime: 'image/png',
      totalSize: BigInt.from(500000),
      thumbnailB64: _miniature,
    );

Future<void> _pump(WidgetTester tester, String? preview, List<String> downloads,
        {String? original}) =>
    pumpScreen(
        tester,
        Scaffold(
            body: Center(
                child: AttachmentCard(
          descriptor: _descriptor(),
          view: AttachmentView(
            attachmentId: 'photo',
            direction: 'incoming',
            state: original == null
                ? AttachmentState.offered
                : AttachmentState.available,
            completedChunks: BigInt.zero,
            chunkCount: BigInt.from(123),
            localPath: original,
            previewPath: preview,
          ),
          own: false,
          busy: false,
          onDownload: downloads.add,
          onCancel: (_) {},
          onOpen: (_) {},
        ))));

void main() {
  testWidgets(
      'an unsupported original displays its clear JPEG before the miniature',
      (tester) async {
    final directory = await tester
        .runAsync(() => Directory.systemTemp.createTemp('mosh-tiff-preview-'));
    addTearDown(() => directory!.delete(recursive: true));
    final original = File('${directory!.path}/original.tiff');
    final preview = File('${directory.path}/preview.jpg');
    await tester.runAsync(() async {
      await original
          .writeAsBytes(img.encodeTiff(img.Image(width: 64, height: 48)));
      await preview
          .writeAsBytes(img.encodeJpg(img.Image(width: 320, height: 240)));
    });
    await _pump(tester, preview.path, [], original: original.path);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    final imagePaths = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<ResizeImage>()
        .map((provider) => (provider.imageProvider as FileImage).file.path);
    expect(imagePaths, contains(preview.path));
    expect(
        find.byWidgetPredicate(
            (widget) => widget is Image && widget.image is MemoryImage),
        findsNothing);
    expect(find.byTooltip('Download'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the clear preview replaces the miniature without completing the original',
      (tester) async {
    final downloads = <String>[];
    await _pump(tester, null, downloads);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('mosh-widget-preview-'));
    final file = File('${directory!.path}/preview.png');
    await tester.runAsync(() => file.writeAsBytes(base64Decode(_miniature)));
    addTearDown(() => directory.delete(recursive: true));
    await _pump(tester, file.path, downloads);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    final image = tester
        .widget<Image>(find.byWidgetPredicate(
            (widget) => widget is Image && widget.image is ResizeImage))
        .image as ResizeImage;
    expect((image.imageProvider as FileImage).file.path, file.path);
    expect(downloads, isEmpty);
    expect(find.byTooltip('Download'), findsOneWidget);
    await tester.tap(find.byTooltip('Download'));
    expect(downloads, ['photo']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing clear preview keeps the miniature visible',
      (tester) async {
    await _pump(
        tester, '${Directory.systemTemp.path}/mosh-missing-preview.jpg', []);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (widget) => widget is Image && widget.image is MemoryImage),
        findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    expect(find.text('photo.png'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
