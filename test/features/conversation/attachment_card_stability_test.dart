// IVO-27: returning to a chat must not resize attachment previews, and the
// message time must not move transfer controls or sit above progress.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';

import '../../support/pump.dart';

final _landscape =
    base64Encode(img.encodeJpg(img.Image(width: 48, height: 32)));

AttachmentDescriptor _descriptor(String? thumbnail,
        {String mime = 'image/jpeg'}) =>
    AttachmentDescriptor(
      attachmentId: 'photo',
      contentHash: 'hash',
      fileName: 'Sunshining Balve.jpg',
      mime: mime,
      totalSize: BigInt.from(11 * 1024 * 1024),
      thumbnailB64: thumbnail,
    );

AttachmentView _view(AttachmentState state, {String? preview}) =>
    AttachmentView(
      attachmentId: 'photo',
      direction: 'incoming',
      state: state,
      completedChunks: BigInt.from(71),
      chunkCount: BigInt.from(100),
      previewPath: preview,
    );

Widget _card(AttachmentDescriptor descriptor, AttachmentView view,
        {Widget? footer}) =>
    Scaffold(
        body: Center(
            child: AttachmentCard(
      descriptor: descriptor,
      view: view,
      own: false,
      busy: false,
      onDownload: (_) {},
      onCancel: (_) {},
      onOpen: (_) {},
      messageFooter: footer,
    )));

Finder get _preview => find.bySemanticsLabel('Open Sunshining Balve.jpg');

Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The cancel button's place within its card, independent of centering.
Rect _cancelInCard(WidgetTester tester) => tester
    .getRect(find.byTooltip('Cancel download'))
    .shift(-tester.getTopLeft(find.byType(AttachmentCard)));

void main() {
  testWidgets('the preview reserves its final height before any decode',
      (tester) async {
    await pumpScreen(tester,
        _card(_descriptor(_landscape), _view(AttachmentState.cancelled)),
        settle: false);
    final reserved = tester.getSize(_preview);
    expect(reserved.height, closeTo(320 / 1.5, 0.5));

    await _decode(tester);
    expect(tester.getSize(_preview), reserved);

    final directory = await tester
        .runAsync(() => Directory.systemTemp.createTemp('mosh-stable-'));
    addTearDown(() => directory!.delete(recursive: true));
    final clear = File('${directory!.path}/preview.jpg');
    await tester.runAsync(() =>
        clear.writeAsBytes(img.encodeJpg(img.Image(width: 320, height: 213))));
    await pumpScreen(
        tester,
        _card(_descriptor(_landscape),
            _view(AttachmentState.cancelled, preview: clear.path)),
        settle: false);
    expect(tester.getSize(_preview), reserved);
    await _decode(tester);
    expect(tester.getSize(_preview), reserved);
  });

  testWidgets('a narrower bubble keeps the media aspect ratio', (tester) async {
    await pumpScreen(
        tester,
        Scaffold(
            body: Center(
                child: SizedBox(
                    width: 240,
                    child: AttachmentCard(
                      descriptor: _descriptor(_landscape),
                      view: _view(AttachmentState.offered),
                      own: false,
                      busy: false,
                      onDownload: (_) {},
                      onCancel: (_) {},
                      onOpen: (_) {},
                    )))),
        settle: false);
    expect(tester.getSize(_preview), const Size(240, 160));
  });

  testWidgets('portrait and unknown sizes stay within the preview bounds',
      (tester) async {
    final portrait =
        base64Encode(img.encodeJpg(img.Image(width: 24, height: 48)));
    await pumpScreen(
        tester, _card(_descriptor(portrait), _view(AttachmentState.offered)),
        settle: false);
    expect(tester.getSize(_preview).height, kAttachmentPreviewMaxHeight);

    final panorama =
        base64Encode(img.encodeJpg(img.Image(width: 48, height: 4)));
    await pumpScreen(
        tester, _card(_descriptor(panorama), _view(AttachmentState.offered)),
        settle: false);
    expect(tester.getSize(_preview).height, kAttachmentPreviewMinHeight);

    await pumpScreen(
        tester, _card(_descriptor('AAAA'), _view(AttachmentState.offered)),
        settle: false);
    final unknown = tester.getSize(_preview).height;
    await _decode(tester);
    expect(tester.getSize(_preview).height, unknown);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a returning chat shows its decoded miniature in the first frame',
      (tester) async {
    final descriptor = _descriptor(_landscape);
    await pumpScreen(tester, _card(descriptor, _view(AttachmentState.offered)),
        settle: false);
    await _decode(tester);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);

    await pumpScreen(tester, const Scaffold(body: Text('elsewhere')));
    await pumpScreen(
        tester, _card(_descriptor(_landscape), _view(AttachmentState.offered)),
        settle: false);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
  });

  testWidgets('time keeps the cancel button in place and stays off progress',
      (tester) async {
    final downloading = _view(AttachmentState.downloading);
    await pumpScreen(
        tester, _card(_descriptor(null, mime: 'application/zip'), downloading));
    final alone = _cancelInCard(tester);

    await pumpScreen(
        tester,
        _card(_descriptor(null, mime: 'application/zip'), downloading,
            footer: const Text('22:20')));
    final cancel = tester.getRect(find.byTooltip('Cancel download'));
    expect(_cancelInCard(tester), alone);
    final time = tester.getRect(find.text('22:20'));
    final meta = tester.getRect(find.textContaining('71%'));
    final progress = tester.getRect(find.byType(LinearProgressIndicator));

    // Like text bubbles, time ends the last line; here that is the progress.
    expect(time.top, greaterThanOrEqualTo(meta.bottom));
    expect(time.center.dy, closeTo(progress.center.dy, 1));
    expect(progress.right, lessThanOrEqualTo(time.left));
    expect(time.right, closeTo(cancel.right, 1));
    expect(tester.takeException(), isNull);
  });
}
