// Widget tests for the shared MediaViewer
// (lib/src/features/shared/media_viewer.dart) -- the 1-в-1 port of React's
// `src/features/private-dm/MediaViewer.tsx`. Pins: the caption + close
// button render, the mime branching (image -> Image.network, video/audio ->
// play_circle_filled placeholder, other -> insert_drive_file_outlined
// placeholder), the close button + backdrop tap close the viewer, the stage
// tap does NOT close, and the Semantics label == file_name (React
// `role=dialog aria-label=file_name`).
//
// The viewer is pumped via `showDialog` (the same path the real
// [showMediaViewer] helper uses) so it renders as a true fullscreen route
// -- mirroring the ConfirmDialog test harness. The image branch uses
// `Image.network`, so the harness installs a global `HttpOverrides` whose
// client throws on connect, keeping the test hermetic (no real network
// fetch) and letting `Image.network`'s `errorBuilder` render
// deterministically.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/media_viewer.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import '../../support/pump.dart';

/// An `HttpOverrides` whose `createHttpClient` throws, so `Image.network`
/// fails fast (no real network I/O) and its `errorBuilder` renders the
/// broken-image fallback deterministically. Installed globally for the
/// image-branch test.
class _NoNetworkOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('no network in tests');
}

AttachmentDescriptor _descriptor({
  required String fileName,
  required String mime,
}) =>
    AttachmentDescriptor(
      attachmentId: 'att-1',
      contentHash: 'h-1',
      fileName: fileName,
      mime: mime,
      totalSize: BigInt.from(1024),
      thumbnailB64: null,
      voice: null,
    );

/// A host that opens [MediaViewer] via `showDialog` on the first
/// post-frame callback (so the dialog opens after the Navigator mounts).
/// The viewer's `onClose` pops the route -- so "close" assertions verify
/// the `MediaViewer` is gone after a tap. Pumped directly via `showDialog`
/// (not the `showMediaViewer` helper) so the tests can pass an explicit
/// `onClose`; the `showMediaViewer` helper has its own contract test below.
class _ViewerHost extends StatefulWidget {
  const _ViewerHost({
    required this.descriptor,
    this.src = 'https://example.invalid/test',
    this.onClose,
  });

  final AttachmentDescriptor descriptor;
  final String src;
  final VoidCallback? onClose;

  @override
  State<_ViewerHost> createState() => _ViewerHostState();
}

class _ViewerHostState extends State<_ViewerHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        // Dismissible so the barrier tap mirrors React's click-anywhere.
        barrierDismissible: true,
        barrierLabel: AppLocalizations.of(context)!.closeViewer,
        builder: (dialogContext) => MediaViewer(
          descriptor: widget.descriptor,
          src: widget.src,
          onClose: widget.onClose ?? () => Navigator.of(dialogContext).pop(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Pumps a localized `MaterialApp` hosting [_ViewerHost], then settles the
/// post-frame callback that opens the viewer. After this returns the
/// `MediaViewer` route is mounted and content assertions can run.
Future<void> _pumpViewer(
  WidgetTester tester, {
  required AttachmentDescriptor descriptor,
  String src = 'https://example.invalid/test',
  VoidCallback? onClose,
}) =>
    pumpScreen(tester,
        _ViewerHost(descriptor: descriptor, src: src, onClose: onClose));

void main() {
  // Pins that the caption (file_name) + the close button render, and the
  // close button's tooltip == the localized `closeViewer` ("Close viewer"
  // in the en locale).
  testWidgets('renders the caption + close button (en)', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'photo.png', mime: 'image/png'),
    );

    // React `.media-viewer-caption` renders the file_name. It also appears
    // inside the image's `semanticLabel`, so `findsNWidgets(2)` is expected
    // -- the caption Text + the Image.network semanticLabel node.
    // (The image branch's `Image.network` `semanticLabel` -- React
    // `alt=file_name` -- is semantics metadata, not a visible `Text`
    // widget, so the caption is the only `Text` rendering the filename on
    // the image branch.)
    expect(find.text('photo.png'), findsOneWidget);
    // The close button (Icons.close, React IconX) renders.
    expect(find.byIcon(Icons.close), findsOneWidget);
    // React `aria-label="Close viewer"` -> localized tooltip.
    expect(find.byTooltip('Close viewer'), findsOneWidget);
  });

  // Pins the image mime branch: an `Image` widget is mounted (React
  // `<img src alt=file_name>`). A global `HttpOverrides` short-circuits the
  // fetch so the errorBuilder renders `broken_image_outlined` -- the test
  // asserts the Image branch was taken, NOT a real network payload.
  testWidgets('image mime mounts Image.network (no real fetch)',
      (tester) async {
    HttpOverrides.global = _NoNetworkOverrides();
    addTearDown(() => HttpOverrides.global = null);
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'photo.png', mime: 'image/png'),
    );

    expect(find.byType(Image), findsOneWidget);
    // No placeholder play/file icon on the image branch.
    expect(find.byIcon(Icons.play_circle_filled), findsNothing);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing);
  });

  // Pins the video mime branch: a placeholder card with
  // `Icons.play_circle_filled` (React `IconPlayerPlayFilled`). No real
  // player is wired (TODO slice-3) -- the test pins the placeholder icon.
  testWidgets('video mime renders the play-circle placeholder', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'clip.mp4', mime: 'video/mp4'),
    );

    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
    // The filename renders TWICE -- the placeholder card's bold
    // `<strong>{file_name}</strong>` AND the `.media-viewer-caption` --
    // exactly mirroring React's double-render.
    expect(find.text('clip.mp4'), findsNWidgets(2));
    // No image on the video branch.
    expect(find.byType(Image), findsNothing);
  });

  // Pins the audio mime branch: a placeholder card with
  // `Icons.play_circle_filled` (React `IconPlayerPlayFilled`).
  testWidgets('audio mime renders the play-circle placeholder', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'song.mp3', mime: 'audio/mpeg'),
    );

    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
    // The filename renders in the placeholder card + the caption.
    expect(find.text('song.mp3'), findsNWidgets(2));
    expect(find.byType(Image), findsNothing);
  });

  // Pins the "other" mime branch: a placeholder card with
  // `Icons.insert_drive_file_outlined` (React `IconFile`).
  testWidgets('other mime renders the file placeholder', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'doc.pdf', mime: 'application/pdf'),
    );

    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
    // The filename renders in the placeholder card + the caption.
    expect(find.text('doc.pdf'), findsNWidgets(2));
    // No play icon on the file branch.
    expect(find.byIcon(Icons.play_circle_filled), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  // Pins that tapping the close button closes the viewer (React
  // `onClick=onClose` on `.media-viewer-close`). The viewer's `onClose`
  // pops the route, so the `MediaViewer` is gone after the tap.
  testWidgets('tapping the close button closes the viewer', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'clip.mp4', mime: 'video/mp4'),
    );
    expect(find.byType(MediaViewer), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(MediaViewer), findsNothing);
  });

  // Pins that tapping the backdrop (outside the stage) closes the viewer
  // (React `onClick=onClose` on `.media-viewer` -- click anywhere closes).
  testWidgets('tapping the backdrop closes the viewer', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'clip.mp4', mime: 'video/mp4'),
    );
    expect(find.byType(MediaViewer), findsOneWidget);

    // Tap the top-left corner -- outside the centered stage, on the
    // backdrop. `barrierDismissible: true` also pops on barrier tap, but
    // the viewer's own backdrop GestureDetector (React `onClick=onClose`)
    // is the faithful close path being pinned here.
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(find.byType(MediaViewer), findsNothing);
  });

  // Pins that tapping the stage (the media itself) does NOT close the
  // viewer (React `.media-viewer-stage` `onClick stopPropagation` --
  // clicking the media does not close the viewer).
  testWidgets('tapping the stage does NOT close the viewer', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'clip.mp4', mime: 'video/mp4'),
    );
    expect(find.byType(MediaViewer), findsOneWidget);

    // Tap the centered placeholder card (the stage) -- the inner
    // GestureDetector swallows the tap (React `stopPropagation`).
    await tester.tap(find.byIcon(Icons.play_circle_filled));
    await tester.pumpAndSettle();

    expect(find.byType(MediaViewer), findsOneWidget);
  });

  testWidgets('the route semantics label is the file_name', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'report.pdf', mime: 'application/pdf'),
    );

    // React `role=dialog aria-label={descriptor.file_name}`. The viewer
    // sets `Semantics(container: true, label: fileName)` on its root; the
    // configured `label` is read straight off the `Semantics` widget's
    // `properties.label` (the React `aria-label` mirror). The
    // `container`/`scopesRoute` flags live on the framework's
    // `SemanticsConfiguration`, not the public `SemanticsProperties`/`SemanticsNode`,
    // and the modal-route scoping (React `aria-modal`) is provided by the
    // `showDialog` host -- so only the `label` is asserted here.
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'report.pdf',
    );
    expect(finder, findsOneWidget);
  });

  // === showMediaViewer helper contract ===

  // Pins that `showMediaViewer` opens the viewer (the caption renders) and
  // the close button pops the route (the viewer disappears).
  testWidgets('showMediaViewer opens the viewer; close pops it',
      (tester) async {
    late BuildContext ctx;
    await pumpScreen(tester, Builder(
      builder: (context) {
        ctx = context;
        return const SizedBox.shrink();
      },
    ), settle: false);

    unawaited(showMediaViewer(
      context: ctx,
      descriptor: _descriptor(fileName: 'clip.mp4', mime: 'video/mp4'),
      src: 'https://example.invalid/test',
    ));
    await tester.pumpAndSettle();

    // The viewer opened: caption (placeholder bold + caption, 2x) + close.
    expect(find.text('clip.mp4'), findsNWidgets(2));
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Close via the close button -> the viewer is gone.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(MediaViewer), findsNothing);
  });
}
