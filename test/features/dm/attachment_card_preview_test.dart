// Widget tests for the IMAGE media-preview branch of the DM attachment
// card (lib/src/features/dm/attachment_card.dart). Pumps `AttachmentCard`
// directly inside a `MaterialApp` with the AppLocalizations delegate so
// the localized state labels resolve, mirroring the established DM
// widget-test pattern but scoped to the card (no Riverpod/DmScreen).
//
// In scope (this atomic): the image-with-thumbnail branch renders a
// non-interactive `Image.memory` preview above the shared name + size +
// state-label bar. Out of scope and asserted absent or unasserted: the
// onOpen tap, the actions row, and the voice
// message branch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/attachment_card.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

// Known-good 1x1 PNG (70 bytes, magic header 0x89 0x50 0x4E 0x47 ...).
// Used as the thumbnail payload for the image and video preview tests.
// `Image.memory` will decode it, but the tests only assert the widget
// mounts (not the decoded pixels), so a tiny PNG is sufficient and keeps
// the test fast.
const _pngThumbB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

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

Future<void> _pump(WidgetTester tester, AttachmentCard card) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: card)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
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
      ),
    );

    // The media-preview branch mounts an Image.memory from the decoded
    // thumbnail bytes.
    expect(find.byType(Image), findsOneWidget);
    // The shared bar still renders the file name and the formatted size.
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.textContaining('4.0 KB'), findsOneWidget);
  });

  testWidgets('image without thumbnail falls back to the file card',
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
      ),
    );

    // No preview: no Image.memory in the tree.
    expect(find.byType(Image), findsNothing);
    // The file-card file icon renders.
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
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
      ),
    );

    // The video-with-thumbnail branch takes the media path this atomic
    // and renders Image.memory. The centered play overlay (in scope
    // this atomic) is asserted in the dedicated overlay test file.
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('audio without thumbnail falls back to the file card',
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
      ),
    );

    // Audio is not isImage/isVideo, so no preview.
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
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
      // React `hasPreview` requires isImage || isVideo.
      thumbnailB64: _pngThumbB64,
    );
    await _pump(
      tester,
      AttachmentCard(
        descriptor: descriptor,
        view: _view(attachmentId: 'att-pdf'),
        own: false,
      ),
    );

    // Pins the `isImage || isVideo` guard: no Image.memory.
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
    expect(find.text('doc.pdf'), findsOneWidget);
  });
}
