// Widget tests for the VIDEO play-overlay on the DM attachment card
// media-preview branch (lib/src/features/conversation/attachment_card.dart).
// Pins React's `<span className="attachment-play" aria-hidden="true">
// <IconPlayerPlayFilled size={20}/>` overlay: a centered
// `Icons.play_circle_filled` renders over the thumbnail image WHEN the
// mime is a video, and nothing renders for an image. The overlay is
// decorative; the preview's open behavior is asserted in the focused card
// tests. The no-thumbnail video case covers the file-card thumb affordance.
//
// The harness mirrors the established DM widget-test pattern (pump
// `AttachmentCard` directly inside a localized `MaterialApp`, find by
// icon / by type), reusing the same 1x1 PNG thumbnail as the preview
// test file.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import '../../support/pump.dart';

// Same known-good 1x1 PNG used in attachment_card_preview_test.dart.
const _pngThumbB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

// Transfer-action callbacks are inert; these tests assert the media overlay
// and the no-thumbnail thumb surface.
void _onDownload(String _) {}
void _onCancel(String _) {}
void _onOpen(AttachmentDescriptor _) {}

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

void main() {
  testWidgets(
      'video with thumbnail renders a centered play overlay over the image',
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

    // The media-preview branch mounts the decoded thumbnail Image.memory.
    expect(find.byType(Image), findsOneWidget);
    // The centered play overlay is present for a video mime: React's
    // `.attachment-play` circle holding the play glyph.
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('image with thumbnail does NOT render a play overlay',
      (tester) async {
    final descriptor = _descriptor(
      attachmentId: 'att-img',
      fileName: 'photo.jpg',
      mime: 'image/jpeg',
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

    // Image still mounts on the media-preview branch.
    expect(find.byType(Image), findsOneWidget);
    // No play overlay for an image mime (React renders the overlay only
    // when `isVideo`).
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('video without thumbnail renders an open thumb (no overlay)',
      (tester) async {
    final descriptor = _descriptor(
      attachmentId: 'att-vid-nothumb',
      fileName: 'clip2.mp4',
      mime: 'video/mp4',
      totalSize: 2048576,
      // No thumbnail: hasPreview is false, so the file-card branch renders
      // (no media preview or thumbnail overlay).
      thumbnailB64: null,
    );
    await _pump(
      tester,
      AttachmentCard(
        descriptor: descriptor,
        view: _view(attachmentId: 'att-vid-nothumb'),
        own: false,
        busy: false,
        onDownload: _onDownload,
        onCancel: _onCancel,
        onOpen: _onOpen,
      ),
    );

    // Pins that the overlay only appears on the media branch (hasPreview
    // requires a thumbnail): with no thumbnail there is no preview at all,
    // so the single play glyph on screen is the file card's open thumb.
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('clip2.mp4'), findsOneWidget);
  });
}
