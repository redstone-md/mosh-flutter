// Widget tests for the shared MediaViewer
// (lib/src/features/shared/media_viewer.dart). Pins: the caption + close
// button render, the mime branching (image -> Image from a file:// URL;
// video/audio without a player -> play_circle_filled placeholder, other ->
// insert_drive_file_outlined placeholder), the close button + backdrop tap
// close the viewer, the stage tap does NOT close, and the Semantics label ==
// file_name.
//
// The viewer is pumped via `showDialog` (the same path the real
// [showMediaViewer] helper uses) so it renders as a true fullscreen route
// -- mirroring the ConfirmDialog test harness. The image test installs a
// global `HttpOverrides` whose client throws on connect, so a file:// image
// that wrongly went to the network shows the broken-image fallback.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/shared/media_viewer.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import '../../support/pump.dart';

/// An `HttpOverrides` whose `createHttpClient` throws, so an image fetched
/// over the network fails fast and renders the broken-image fallback.
class _NoNetworkOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('no network in tests');
}

/// A valid 1x1 opaque PNG.
const List<int> _kOnePixelPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, //
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, //
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB0, 0x00, 0x00, 0x00, //
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
];

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
    this.sent,
    this.onSave,
    this.onClose,
  });

  final AttachmentDescriptor descriptor;
  final String src;
  final String? sent;
  final VoidCallback? onSave;
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
        // Dismissible so a barrier tap closes the viewer.
        barrierDismissible: true,
        barrierLabel: AppLocalizations.of(context)!.closeViewer,
        builder: (dialogContext) => MediaViewer(
          descriptor: widget.descriptor,
          src: widget.src,
          sent: widget.sent,
          onSave: widget.onSave,
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
  String? sent,
  VoidCallback? onSave,
  VoidCallback? onClose,
}) =>
    pumpScreen(
        tester,
        _ViewerHost(
            descriptor: descriptor,
            src: src,
            sent: sent,
            onSave: onSave,
            onClose: onClose));

void main() {
  testWidgets('the bar names the file and who sent it, and offers the way out',
      (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'photo.png', mime: 'image/png'),
      sent: 'Maya Chen, Nov 21, 2026 9:38',
    );

    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('Maya Chen, Nov 21, 2026 9:38'), findsOneWidget);
    expect(find.byTooltip('Close viewer'), findsOneWidget);
  });

  testWidgets('a file on this device is saved from the bar', (tester) async {
    var saves = 0;
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'photo.png', mime: 'image/png'),
      onSave: () => saves++,
    );

    await tester.tap(find.byTooltip('Save as…'));
    expect(saves, 1);
    // Saving is not leaving.
    expect(find.byType(MediaViewer), findsOneWidget);
  });

  testWidgets('a file still arriving cannot be saved yet', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'doc.pdf', mime: 'application/pdf'),
    );

    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, MoshIcons.download))
            .onPressed,
        isNull);
    // No way out to offer yet, so none is promised.
    expect(find.text('No preview for this file'), findsOneWidget);
    expect(find.text('Save it to open it in another app'), findsNothing);
  });

  testWidgets('a file without a preview offers to be saved instead',
      (tester) async {
    var saves = 0;
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'route.gpx', mime: 'application/gpx'),
      onSave: () => saves++,
    );

    expect(find.text('No preview for this file'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save as…'));
    expect(saves, 1);
  });

  // A downloaded attachment arrives as a `file://` URL. It must load from
  // disk -- `NetworkImage` cannot fetch that scheme, and the viewer used to
  // show the broken-image fallback for every local picture.
  testWidgets('a file:// image loads from disk, not the network',
      (tester) async {
    HttpOverrides.global = _NoNetworkOverrides();
    addTearDown(() => HttpOverrides.global = null);
    // Real file I/O and image decoding need the real event loop, so the
    // whole test body runs under `runAsync`.
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('mosh-viewer');
      addTearDown(() => dir.delete(recursive: true));
      // A non-ASCII name with spaces and a comma, as the runtime writes it.
      final file = File('${dir.path}/Изображение 29 авг., 20_55.png');
      await file.writeAsBytes(_kOnePixelPng);

      await _pumpViewer(
        tester,
        descriptor: _descriptor(fileName: 'photo.png', mime: 'image/png'),
        src: Uri.file(file.path).toString(),
      );
      final image = tester.element(find.byType(Image));
      await precacheImage((image.widget as Image).image, image,
          onError: (_, __) {});
      await tester.pump();
    });

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(MoshIcons.imageBroken), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
  });

  // This isolate has no media_kit backend, so no player can be made and
  // the stage says so instead of standing empty.
  testWidgets('a video that cannot play here says so', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'clip.mp4', mime: 'video/mp4'),
      onSave: () {},
    );

    expect(find.text('This video cannot be played here'), findsOneWidget);
    expect(find.text('Save it to watch it in another app'), findsOneWidget);
  });

  testWidgets('a sound that cannot play here says so', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'song.mp3', mime: 'audio/mpeg'),
      onSave: () {},
    );

    expect(find.text('This recording cannot be played here'), findsOneWidget);
    expect(find.text('Save it to listen to it in another app'), findsOneWidget);
  });

  // Pins that tapping the close button closes the viewer. The viewer's
  // `onClose` pops the route, so the `MediaViewer` is gone after the tap.
  testWidgets('tapping the close button closes the viewer', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'clip.mp4', mime: 'video/mp4'),
    );
    expect(find.byType(MediaViewer), findsOneWidget);

    await tester.tap(find.byIcon(MoshIcons.close));
    await tester.pumpAndSettle();

    expect(find.byType(MediaViewer), findsNothing);
  });

  // Pins that tapping the backdrop (outside the stage) closes the viewer
  // (a tap anywhere on the backdrop closes).
  testWidgets('tapping the backdrop closes the viewer', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'clip.mp4', mime: 'video/mp4'),
    );
    expect(find.byType(MediaViewer), findsOneWidget);

    // Tap the room at the stage's side, beside the media.
    await tester.tapAt(const Offset(5, 300));
    await tester.pumpAndSettle();

    expect(find.byType(MediaViewer), findsNothing);
  });

  testWidgets('a press on the bar does not close the viewer', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'clip.mp4', mime: 'video/mp4'),
    );

    await tester.tap(find.text('clip.mp4'));
    await tester.pumpAndSettle();

    expect(find.byType(MediaViewer), findsOneWidget);
  });

  // Pins that tapping the stage (the media itself) does NOT close the
  // viewer (a click on the media does not close the viewer).
  testWidgets('tapping the stage does NOT close the viewer', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'clip.mp4', mime: 'video/mp4'),
    );
    expect(find.byType(MediaViewer), findsOneWidget);

    // Tap the note in the middle (the stage) -- the inner GestureDetector
    // swallows the tap.
    await tester.tap(find.text('This video cannot be played here'));
    await tester.pumpAndSettle();

    expect(find.byType(MediaViewer), findsOneWidget);
  });

  testWidgets('the route semantics label is the file_name', (tester) async {
    await _pumpViewer(
      tester,
      descriptor: _descriptor(fileName: 'report.pdf', mime: 'application/pdf'),
    );

    // The viewer sets `Semantics(container: true, label: fileName)` on its
    // root; the configured `label` is read straight off the `Semantics`
    // widget's `properties.label`. The
    // `container`/`scopesRoute` flags live on the framework's
    // `SemanticsConfiguration`, not the public `SemanticsProperties`/`SemanticsNode`,
    // and the modal-route scoping is provided by the
    // `showDialog` host -- so only the `label` is asserted here.
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'report.pdf',
    );
    expect(finder, findsOneWidget);
  });

  // === showMediaViewer helper contract ===

  testWidgets('a file on this device can be saved, one still arriving cannot',
      (tester) async {
    late BuildContext ctx;
    await pumpScreen(tester, Builder(builder: (context) {
      ctx = context;
      return const SizedBox.shrink();
    }));
    for (final (src, canSave) in [
      ('file:///downloads/notes.txt', true),
      ('https://example.invalid/stream', false),
    ]) {
      unawaited(showMediaViewer(
        context: ctx,
        descriptor: _descriptor(fileName: 'notes.txt', mime: 'text/plain'),
        src: src,
      ));
      await tester.pumpAndSettle();

      final save = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, MoshIcons.download));
      expect(save.onPressed, canSave ? isNotNull : isNull, reason: src);
      await tester.tap(find.byTooltip('Close viewer'));
      await tester.pumpAndSettle();
    }
  });

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

    // The viewer opened: the bar names the file and offers the way out.
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(find.byIcon(MoshIcons.close), findsOneWidget);

    // Close via the close button -> the viewer is gone.
    await tester.tap(find.byIcon(MoshIcons.close));
    await tester.pumpAndSettle();

    expect(find.byType(MediaViewer), findsNothing);
  });
}
