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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_icons.dart';
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
    expect(find.byIcon(MoshIcons.play), findsNothing);
    await tester.tap(find.byType(Image));
    expect(_openCount, 1);
    expect(_opened, descriptor);
    // The shared bar still renders the file name and the formatted size.
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.textContaining('4.0 KB'), findsOneWidget);
  });

  testWidgets('image without thumbnail opens from its card', (tester) async {
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
    expect(find.byIcon(MoshIcons.download), findsOneWidget);
    // The plate owns the accessible action, so there is exactly one Open
    // announcement; the whole card is the pointer's target.
    expect(find.bySemanticsLabel('Open photo2.png'), findsOneWidget);
    final semanticsHandle = tester.ensureSemantics();
    final thumbSemantics =
        tester.getSemantics(find.byIcon(MoshIcons.download)).getSemanticsData();
    expect(thumbSemantics.label, 'Open photo2.png');
    expect(thumbSemantics.hasAction(SemanticsAction.tap), isTrue);
    semanticsHandle.dispose();
    await tester.tap(find.byIcon(MoshIcons.download));
    expect(_openCount, 1);
    expect(_opened, descriptor);
    // The file name still renders.
    expect(find.text('photo2.png'), findsOneWidget);
  });

  testWidgets('video with thumbnail renders the media preview and play overlay',
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

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(MoshIcons.play), findsOneWidget);
  });

  testWidgets('video without thumbnail opens from its card', (tester) async {
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
    expect(find.byIcon(MoshIcons.download), findsOneWidget);
    expect(find.bySemanticsLabel('Open clip2.mp4'), findsOneWidget);
    await tester.tap(find.byIcon(MoshIcons.download));
    expect(_openCount, 1);
    expect(_opened, descriptor);
  });

  testWidgets('audio without thumbnail opens from its card', (tester) async {
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
    expect(find.byIcon(MoshIcons.download), findsOneWidget);
    expect(find.bySemanticsLabel('Open song.mp3'), findsOneWidget);
    await tester.tap(find.byIcon(MoshIcons.download));
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
    expect(find.bySemanticsLabel('Open doc.pdf'), findsNothing);
    expect(find.bySemanticsLabel('Download doc.pdf'), findsOneWidget);
    await tester.tap(find.text('doc.pdf'));
    expect(_openCount, 0);
  });

  testWidgets('a failed file offers to try again and does not open',
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

    expect(find.bySemanticsLabel('Retry broken.pdf'), findsOneWidget);
    expect(find.bySemanticsLabel('Open broken.pdf'), findsNothing);
    await tester.tap(find.byIcon(MoshIcons.refresh));
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
    expect(find.byIcon(MoshIcons.imageBroken), findsOneWidget);
    expect(find.bySemanticsLabel('Open photo3.png'), findsOneWidget);
    expect(find.text('photo3.png'), findsOneWidget);
  });

  group('a picture in transfer', () {
    AttachmentCard card(AttachmentState state, List<String> calls) {
      final descriptor = _descriptor(
        attachmentId: 'att-photo',
        fileName: 'ridge.jpg',
        mime: 'image/jpeg',
        totalSize: 4096,
        thumbnailB64: _pngThumbB64,
      );
      return AttachmentCard(
        descriptor: descriptor,
        view: _view(
            attachmentId: 'att-photo', state: state, completed: 58, total: 100),
        own: false,
        busy: false,
        onDownload: (id) => calls.add('download $id'),
        onCancel: (id) => calls.add('cancel $id'),
        onOpen: _onOpen,
      );
    }

    testWidgets('shows how far it has come, and its ring stops it',
        (tester) async {
      final calls = <String>[];
      await pumpScreen(
          tester,
          Scaffold(
              body: Center(child: card(AttachmentState.downloading, calls))),
          settle: false);
      expect(find.text('58% of 4.0 KB'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel download'));
      expect(calls, ['cancel att-photo']);
      expect(_openCount, 0);
      // The ring is a control for a screen reader and a keyboard too.
      final handle = tester.ensureSemantics();
      expect(
          tester.getSemantics(
              find.bySemanticsLabel('Cancel download for ridge.jpg').first),
          isSemantics(isButton: true, hasTapAction: true));
      handle.dispose();
      Focus.of(tester.element(find.byType(CircularProgressIndicator)))
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, ['cancel att-photo', 'cancel att-photo']);
    });

    testWidgets('that failed says so and offers to try again', (tester) async {
      final calls = <String>[];
      await _pump(tester, card(AttachmentState.failed, calls));
      expect(find.text('Could not load'), findsOneWidget);
      await tester.tap(find.byTooltip('Retry'));
      expect(calls, ['download att-photo']);
    });
  });

  testWidgets('a long name is cut in the middle and keeps its extension',
      (tester) async {
    const name = 'trail-map-with-every-waypoint-and-campsite-final-v3.zip';
    await _pump(
      tester,
      AttachmentCard(
        descriptor: _descriptor(
            attachmentId: 'att-long',
            fileName: name,
            mime: 'application/zip',
            totalSize: 1024),
        view: _view(attachmentId: 'att-long'),
        own: false,
        busy: false,
        onDownload: _onDownload,
        onCancel: _onCancel,
        onOpen: _onOpen,
      ),
    );
    final shown = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data!)
        .firstWhere((data) => data.contains('…'));
    expect(shown, startsWith('trail-map'));
    expect(shown, endsWith('al-v3.zip'));
    expect(find.bySemanticsLabel(RegExp(RegExp.escape(name))), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cut never halves an emoji in a name', (tester) async {
    final name = '${'🏕️' * 40}.zip';
    await _pump(
      tester,
      AttachmentCard(
        descriptor: _descriptor(
            attachmentId: 'att-emoji',
            fileName: name,
            mime: 'application/zip',
            totalSize: 1024),
        view: _view(attachmentId: 'att-emoji'),
        own: false,
        busy: false,
        onDownload: _onDownload,
        onCancel: _onCancel,
        onOpen: _onOpen,
      ),
    );
    final shown = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data!)
        .firstWhere((data) => data.contains('…'));
    final parts = shown.split('…');
    // Whole tents on both sides of the cut: no lone half of a pair.
    expect(parts.first.replaceAll('🏕️', ''), isEmpty);
    expect(parts.last, endsWith('.zip'));
    expect(parts.last.replaceAll('🏕️', ''), '.zip');
  });
}
