// Tests for the desktop drag-and-drop attach slice (React ChatComposer.tsx
// 8-43 parity). Two layers:
//   1. `ingestAttachment` unit tests -- the DRY helper shared with the
//      paperclip picker. Synthesize a tiny PNG in-memory via the `image`
//      package (same as thumbnail_test.dart, no fixture file), assert it
//      builds a PickedAttachment with the PNG mime + a JPEG thumbnail, and
//      returns null over the 50 MB ceiling.
//   2. `ChatDropZone` widget tests driven through desktop_drop's real
//      MethodChannel seam (mirrors desktop_drop's own channel_linux_test):
//      pump the zone inside a localized MaterialApp, push an inbound
//      `desktop_drop` method call (`entered`/`exited`/`performOperation`),
//      and assert the overlay shows `l.chatDropHint` while dragging and that
//      a real dropped file ingests through `onAttach`.
import 'dart:async' show Completer;
import 'dart:convert' show base64Decode;
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data' show ByteData, Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, StandardMethodCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart'
    show AttachmentPickError, PickedAttachment, ingestAttachment;
import 'package:mosh/src/features/shared/chat_drop_zone.dart' show ChatDropZone;

Uint8List _png(int w, int h, int rgb) {
  final image = img.Image(width: w, height: h);
  img.fill(image,
      color: img.ColorRgb8((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF));
  return Uint8List.fromList(img.encodePng(image));
}

/// Pushes an inbound platform message on the `desktop_drop` channel so the
/// plugin's `init()` handler fires `_notifyEvent` -> the DropTarget's
/// listener. Mirrors desktop_drop's own channel_linux_test.dart.
Future<void> _invokePlatformMethod(MethodCall call) async {
  final codec = const StandardMethodCodec();
  final completer = Completer<ByteData?>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'desktop_drop',
    codec.encodeMethodCall(call),
    completer.complete,
  );
  await completer.future;
}

String _tempPath(String name) {
  // Join with the OS separator so cross_file's `XFile.name` (which splits on
  // `Platform.pathSeparator`) yields just `name` -- mirrors how a real OS
  // drop delivers a backslash-separated path on Windows.
  return '${Directory.systemTemp.path}${Platform.pathSeparator}$name';
}

void main() {
  group('ingestAttachment', () {
    test('builds a PickedAttachment with the PNG mime + a JPEG thumbnail',
        () async {
      final bytes = _png(64, 48, 0x112233);
      final picked = await ingestAttachment(
        bytes: bytes,
        fileName: 'drop.png',
        maxBytes: 50 * 1024 * 1024,
      );
      expect(picked, isNotNull);
      expect(picked!.fileName, 'drop.png');
      // package:mime infers image/png from the .png extension (file_picker /
      // desktop_drop expose no MIME unlike the browser File.type).
      expect(picked.mime, 'image/png'); // promoted by the picked! above
      // dataBase64 round-trips to the original bytes.
      expect(base64Decode(picked.dataBase64), bytes);
      // thumbnail is a JPEG preview (FF D8 FF magic) -- null only for
      // non-images / decode failures (React createThumbnail parity).
      expect(picked.thumbnailBase64, isNotNull);
      final thumb = base64Decode(picked.thumbnailBase64!);
      expect(thumb[0], 0xFF);
      expect(thumb[1], 0xD8);
      expect(thumb[2], 0xFF);
    });

    test('returns null when bytes exceed maxBytes (caller fires onError)',
        () async {
      final bytes = _png(8, 8, 0x000000);
      final picked = await ingestAttachment(
        bytes: bytes,
        fileName: 'drop.png',
        maxBytes: 1, // ceiling below the PNG size -> reject
      );
      expect(picked, isNull);
    });

    test('infers an empty mime for an unknown extension', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final picked = await ingestAttachment(
        bytes: bytes,
        fileName: 'blob.dat',
        maxBytes: 50 * 1024 * 1024,
      );
      expect(picked, isNotNull);
      // The gateway treats an empty mime as application/octet-stream.
      expect(picked!.mime, ''); // promote once; picked is PickedAttachment?
      expect(picked.thumbnailBase64, isNull); // not an image -> no thumbnail
    });
  });

  group('ChatDropZone', () {
    late File tempPng;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // A real temp PNG so `DropItemFile(path).readAsBytes()` (the drop
      // path) has bytes to read -- no path_provider plugin needed
      // (app_data_dir_test convention: dart:io Directory.systemTemp).
      tempPng = File(
        _tempPath('mosh-drop-${DateTime.now().microsecondsSinceEpoch}.png'),
      );
      await tempPng.writeAsBytes(_png(32, 24, 0x778899));
    });

    tearDown(() async {
      // Best-effort cleanup: on Windows a just-closed file handle can still
      // be locked for an instant, so swallow the rare delete error rather
      // than flake the test run. Leftover temp files are harmless.
      try {
        if (await tempPng.exists()) await tempPng.delete();
      } on Exception {
        // ignore -- best-effort
      }
    });

    Future<void> pumpZone(
      WidgetTester tester, {
      required bool disabled,
      required void Function(PickedAttachment) onAttach,
      required void Function(AttachmentPickError) onError,
    }) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          // Sized so the drop point (400,300) is inside the render box and
          // the DropTarget's paint-bounds check passes.
          body: SizedBox(
            width: 800,
            height: 600,
            child: ChatDropZone(
              disabled: disabled,
              onAttach: onAttach,
              onError: onError,
              child: const Center(child: Text('messages')),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the chatDropHint overlay while a file is dragging',
        (tester) async {
      await pumpZone(
        tester,
        disabled: false,
        onAttach: (_) {},
        onError: (_) {},
      );
      // Before drag: no overlay hint, only the message-list child.
      expect(find.text('Drop a file to share it'), findsNothing);
      expect(find.text('messages'), findsOneWidget);

      // Drag-enter at the widget center -> dragging=true -> overlay renders.
      await _invokePlatformMethod(
        const MethodCall('entered', [400.0, 300.0]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Drop a file to share it'), findsOneWidget);

      // Drag-exit -> dragging=false -> overlay disappears.
      await _invokePlatformMethod(
        const MethodCall('exited', [400.0, 300.0]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Drop a file to share it'), findsNothing);
    });

    testWidgets('ingests a dropped file through onAttach (end-to-end)',
        (tester) async {
      PickedAttachment? attached;
      AttachmentPickError? errored;
      Uint8List? expectedBytes; // read inside runAsync (real I/O; fake clock stalls)
      await pumpZone(
        tester,
        disabled: false,
        onAttach: (a) => attached = a,
        onError: (e) => errored = e,
      );
      // Enter (so _status != idle -- performOperation requires non-idle on
      // non-Linux, per drop_target.dart), then drop the temp PNG path.
      await _invokePlatformMethod(
        const MethodCall('entered', [400.0, 300.0]),
      );
      await tester.pump();
      // Run the drop on the REAL async runner: _onDragDone awaits a real
      // file read (cross_file -> dart:io) + the `image` decode, which need
      // the live event loop. Under the test's fake clock that I/O stalls.
      await tester.runAsync(() async {
        await _invokePlatformMethod(
          MethodCall('performOperation', [tempPng.path]),
        );
        // Spin until the ingest future chain settles (readAsBytes ->
        // ingestAttachment -> createThumbnail -> onAttach). Bounded so a
        // stalled read fails fast instead of hanging the run.
        for (var i = 0; i < 400 && attached == null && errored == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        // Read the expected bytes on the real runner too (dart:io under the
        // fake clock would stall, same as the drop's readAsBytes).
        expectedBytes = await tempPng.readAsBytes();
      });
      // pump (not pumpAndSettle) to flush the setState that cleared the
      // overlay; pumpAndSettle can loop on the CustomPaint repaint.
      await tester.pump();
      await tester.pump();

      expect(errored, isNull);
      expect(attached, isNotNull);
      expect(attached!.fileName, tempPng.uri.pathSegments.last);
      expect(attached!.mime, 'image/png');
      expect(base64Decode(attached!.dataBase64), expectedBytes);
      expect(attached!.thumbnailBase64, isNotNull);
    });

    testWidgets('disabled: no overlay while dragging (React no-op parity)',
        (tester) async {
      await pumpZone(
        tester,
        disabled: true,
        onAttach: (_) => fail('onAttach must not fire while disabled'),
        onError: (_) => fail('onError must not fire while disabled'),
      );
      // enable=false -> DropTarget never registers its raw listener, so the
      // inbound `entered` event finds no DropTarget and no overlay shows.
      await _invokePlatformMethod(
        const MethodCall('entered', [400.0, 300.0]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Drop a file to share it'), findsNothing);
    });
  });
}
