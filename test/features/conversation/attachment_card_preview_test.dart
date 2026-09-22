// Widget tests for the IMAGE media-preview branch of the DM attachment
// card (lib/src/features/conversation/attachment_card.dart). Pumps `AttachmentCard`
// directly inside a `MaterialApp` with the AppLocalizations delegate so
// the localized state labels resolve, mirroring the established DM
// widget-test pattern but scoped to the card (no Riverpod/DmScreen).
//
// In scope (this atomic): the image-with-thumbnail branch renders a tappable
// `Image.memory` preview above the shared name + size + state-label bar. The
// no-thumbnail viewable and non-viewable file-card behavior is covered by the
// focused tests below.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import '../../support/pump.dart';

// Known-good 1x1 PNG (70 bytes, magic header 0x89 0x50 0x4E 0x47 ...).
// Used as the thumbnail payload for the image and video preview tests.
// `Image.memory` will decode it, but the tests only assert the widget
// mounts (not the decoded pixels), so a tiny PNG is sufficient and keeps
// the test fast.
const _pngThumbB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

// Transfer-action callbacks are inert; these tests focus on the thumb and
// media-preview surfaces while tracking the shared onOpen callback.
void _onDownload(String _) {}
void _onCancel(String _) {}
int _openCount = 0;
AttachmentDescriptor? _opened;

void _onOpen(AttachmentDescriptor descriptor) {
  _openCount++;
  _opened = descriptor;
}

AttachmentDescriptor _descriptor({
  required String attachmentId,
  required String fileName,
  required String mime,
  required int totalSize,
  String? thumbnailB64,
}) =>
    AttachmentDescriptor(
      attachmentId: attachmentId,
      contentHash: 'h-$attachmentId',
      fileName: fileName,
      mime: mime,
      totalSize: BigInt.from(totalSize),
      thumbnailB64: thumbnailB64,
      voice: null,
    );

AttachmentView _view({
  required String attachmentId,
  String direction = 'incoming',
  AttachmentState state = AttachmentState.offered,
  int completed = 0,
  int total = 0,
}) =>
    AttachmentView(
      attachmentId: attachmentId,
      direction: direction,
      state: state,
      completedChunks: BigInt.from(completed),
      chunkCount: BigInt.from(total),
      localPath: null,
    );

Future<void> _pump(WidgetTester tester, AttachmentCard card) =>
    pumpScreen(tester, Scaffold(body: Center(child: card)));

void _resetOpenSpy() {
  _openCount = 0;
  _opened = null;
}

void main() {
  setUp(_resetOpenSpy);

  testWidgets(
      'image with thumbnail renders the Image.memory preview + name + size',
      (tester) async {
    final descriptor = _descriptor(
      attachmentId: 'att-img',
      fileName: 'photo.png',
      mime: 'image/png',
      totalSize: 4096,
      thumbnailB64: _pngThumbB64,
    );
    await _pump(
      tester,
      AttachmentCard(
        descriptor: descriptor,
        view: _view(attachmentId: 'att-img'),
        own: false,
        busy: false,
        onDownload: _onDownload,
        onCancel: _onCancel,
        onOpen: _onOpen,
      ),
    );

    // The media-preview branch mounts an Image.memory from the decoded
    // thumbnail bytes and keeps the open surface.
    expect(find.byType(Image), findsOneWidget);
    expect(find.bySemanticsLabel('Open photo.png'), findsOneWidget);
    await tester.tap(find.byType(Image));
    expect(_openCount, 1);
    expect(_opened, descriptor);
    // The shared bar still renders the file name and the formatted size.
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.textContaining('4.0 KB'), findsOneWidget);
  });

  testWidgets('image without thumbnail renders an open thumb button',
      (tester) async {
    final descriptor = _descriptor(
      attachmentId: 'att-img-nothumb',
      fileName: 'photo2.png',
      mime: 'image/png',
      totalSize: 1024,
      thumbnailB64: null,
    );
    await _pump(
      tester,
      AttachmentCard(
        descriptor: descriptor,
        view: _view(attachmentId: 'att-img-nothumb'),
        own: false,
        busy: false,
        onDownload: _onDownload,
        onCancel: _onCancel,
        onOpen: _onOpen,
      ),
    );

    // No preview: no Image.memory in the tree.
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    // The thumb owns the accessible action; IconButton's visual tooltip is
    // excluded from semantics, so there is exactly one Open announcement.
    expect(find.bySemanticsLabel('Open photo2.png'), findsOneWidget);
    final thumbButton = find.ancestor(
      of: find.byIcon(Icons.play_arrow),
      matching: find.byType(InkWell),
    );
    expect(thumbButton, findsOneWidget);
    // The thumb button is a fixed 40x40 square.
    expect(tester.getSize(thumbButton), const Size(40, 40));
    final semanticsHandle = tester.ensureSemantics();
    final thumbSemantics =
        tester.getSemantics(find.byIcon(Icons.play_arrow)).getSemanticsData();
    expect(thumbSemantics.label, 'Open photo2.png');
    expect(thumbSemantics.hasAction(SemanticsAction.tap), isTrue);
    semanticsHandle.dispose();
    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(_openCount, 1);
    expect(_opened, descriptor);
    // The file name still renders.
    expect(find.text('photo2.png'), findsOneWidget);
  });

  testWidgets(
      'video with thumbnail renders the media preview (play overlay covered in the dedicated overlay test)',
      (tester) async {
    final descriptor = _descriptor(
      attachmentId: 'att-vid',
      fileName: 'clip.mp4',
      mime: 'video/mp4',
      totalSize: 1048576,
      thumbnailB64: _pngThumbB64,
    );
    await _pump(
      tester,
      AttachmentCard(
        descriptor: descriptor,
        view: _view(attachmentId: 'att-vid'),
        own: false,
        busy: false,
        onDownload: _onDownload,
        onCancel: _onCancel,
        onOpen: _onOpen,
      ),
    );

    // The video-with-thumbnail branch takes the media path this atomic
    // and renders Image.memory. The centered play overlay (in scope
    // this atomic) is asserted in the dedicated overlay test file.
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('video without thumbnail opens from the thumb button',
      (tester) async {
    final descriptor = _descriptor(
      attachmentId: 'att-vid-nothumb-open',
      fileName: 'clip2.mp4',
      mime: 'video/mp4',
      totalSize: 2048576,
    );
    await _pump(
      tester,
      AttachmentCard(
        descriptor: descriptor,
        view: _view(attachmentId: 'att-vid-nothumb-open'),
        own: false,
        busy: false,
        onDownload: _onDownload,
        onCancel: _onCancel,
        onOpen: _onOpen,
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.bySemanticsLabel('Open clip2.mp4'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(_openCount, 1);
    expect(_opened, descriptor);
  });

  testWidgets('audio without thumbnail renders an open thumb button',
      (tester) async {
    final descriptor = _descriptor(
      attachmentId: 'att-audio',
      fileName: 'song.mp3',
      mime: 'audio/mpeg',
      totalSize: 2048,
      thumbnailB64: null,
    );
    await _pump(
      tester,
      AttachmentCard(
        descriptor: descriptor,
        view: _view(attachmentId: 'att-audio'),
        own: false,
        busy: false,
        onDownload: _onDownload,
        onCancel: _onCancel,
        onOpen: _onOpen,
      ),
    );

    // Audio is viewable without a thumbnail, but it is not a media preview.
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.bySemanticsLabel('Open song.mp3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(_openCount, 1);
    expect(_opened, descriptor);
    expect(find.text('song.mp3'), findsOneWidget);
  });

  testWidgets(
      'non-viewable mime (pdf) with a thumbnail does NOT take the media branch',
      (tester) async {
    final descriptor = _descriptor(
      attachmentId: 'att-pdf',
      fileName: 'doc.pdf',
      mime: 'application/pdf',
      totalSize: 8192,
      // A PDF that happens to carry a thumbnail still does not qualify:
      // the media preview only covers images and videos.
      thumbnailB64: _pngThumbB64,
    );
    await _pump(
      tester,
      AttachmentCard(
        descriptor: descriptor,
        view: _view(attachmentId: 'att-pdf'),
        own: false,
        busy: false,
        onDownload: _onDownload,
        onCancel: _onCancel,
        onOpen: _onOpen,
      ),
    );

    // Pins the `isImage || isVideo` guard: no Image.memory.
    expect(find.byType(Image), findsNothing);
    final fileIcon = find.byIcon(Icons.insert_drive_file_outlined);
    expect(fileIcon, findsOneWidget);
    expect(
      find.ancestor(of: fileIcon, matching: find.byType(IconButton)),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Open doc.pdf'), findsNothing);
    expect(find.byType(IconButton), findsOneWidget);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNotNull);
    await tester.tap(find.byIcon(Icons.insert_drive_file_outlined));
    expect(_openCount, 0);
    expect(find.text('doc.pdf'), findsOneWidget);
  });

  testWidgets('failed non-viewable attachment keeps a non-tappable error icon',
      (tester) async {
    final descriptor = _descriptor(
      attachmentId: 'att-failed-pdf',
      fileName: 'broken.pdf',
      mime: 'application/pdf',
      totalSize: 8192,
    );
    await _pump(
      tester,
      AttachmentCard(
        descriptor: descriptor,
        view: _view(
          attachmentId: 'att-failed-pdf',
          state: AttachmentState.failed,
        ),
        own: false,
        busy: false,
        onDownload: _onDownload,
        onCancel: _onCancel,
        onOpen: _onOpen,
      ),
    );

    final errorIcon = find.byIcon(Icons.error_outline);
    expect(errorIcon, findsOneWidget);
    expect(
      find.ancestor(of: errorIcon, matching: find.byType(IconButton)),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Open broken.pdf'), findsNothing);
    await tester.tap(errorIcon);
    expect(_openCount, 0);
  });

  // Regression (CodeAnt PR #17): a malformed server thumbnail used to
  // throw base64Decode's FormatException during build -- the
  // Image.memory errorBuilder can never catch it, and the whole
  // conversation failed to render. The decode is now defensive: the
  // broken-image fallback renders instead.
  testWidgets(
      'malformed base64 thumbnail renders the broken-image fallback, '
      'not an exception', (tester) async {
    final descriptor = _descriptor(
      attachmentId: 'att-bad-thumb',
      fileName: 'photo3.png',
      mime: 'image/png',
      totalSize: 2048,
      // Not valid base64: base64Decode throws FormatException.
      thumbnailB64: '!!!not-base64!!!',
    );
    await _pump(
      tester,
      AttachmentCard(
        descriptor: descriptor,
        view: _view(attachmentId: 'att-bad-thumb'),
        own: false,
        busy: false,
        onDownload: _onDownload,
        onCancel: _onCancel,
        onOpen: _onOpen,
      ),
    );

    // The fallback icon renders (Image.memory's errorBuilder) and the card
    // survives: the name + open semantics are still there.
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.bySemanticsLabel('Open photo3.png'), findsOneWidget);
    expect(find.text('photo3.png'), findsOneWidget);
  });
}
