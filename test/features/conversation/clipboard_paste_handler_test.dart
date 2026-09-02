// Unit tests for the paste-to-attach decision logic (the pure mappers +
// format picker in clipboard_paste_handler.dart). The platform-channel read
// (`ClipboardReader.readClipboard`) is NOT exercised here -- only the
// synchronous format selection + mime/extension mapping, which is what the
// spec locks in. A fake `ClipboardDataReader` answers `canProvide` from a
// seeded format list.
import 'package:flutter/foundation.dart'
    show FlutterError, FlutterErrorDetails;
import 'package:flutter/widgets.dart' show PasteTextIntent;
import 'package:flutter/services.dart' show SelectionChangedCause;
import 'package:flutter_test/flutter_test.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'package:mosh/src/features/conversation/clipboard_paste_handler.dart'
    show PasteImageAction, extensionForFormat, mimeForFormat, pickImageFormat;
import 'package:mosh/src/features/shared/attachment_picker.dart'
    show AttachmentPickError, PickedAttachment;

/// Minimal fake reader: `canProvide` answers from the seeded format list,
/// which controls which `pickImageFormat` branch fires. Every other member
/// goes through `noSuchMethod` -- the picker never calls them.
class _FakeReader implements ClipboardDataReader {
  _FakeReader(this.formats);
  final List<DataFormat> formats;

  @override
  List<DataFormat> getFormats(List<DataFormat> allFormats) =>
      allFormats.where(formats.contains).toList();

  @override
  bool canProvide(DataFormat format) => formats.contains(format);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('pickImageFormat', () {
    test('png priority over jpeg when both present', () {
      final reader = _FakeReader(const [Formats.png, Formats.jpeg]);
      expect(identical(pickImageFormat(reader), Formats.png), isTrue);
    });

    test('jpeg picked when png absent', () {
      final reader = _FakeReader(const [Formats.jpeg, Formats.gif]);
      expect(identical(pickImageFormat(reader), Formats.jpeg), isTrue);
    });

    test('webp picked before tiff', () {
      final reader = _FakeReader(const [Formats.webp, Formats.tiff]);
      expect(identical(pickImageFormat(reader), Formats.webp), isTrue);
    });

    test('tiff picked when only tiff present', () {
      final reader = _FakeReader(const [Formats.tiff]);
      expect(identical(pickImageFormat(reader), Formats.tiff), isTrue);
    });

    test('returns null when clipboard holds only plain text', () {
      final reader = _FakeReader(const [Formats.plainText]);
      expect(pickImageFormat(reader), isNull);
    });

    test('returns null for empty clipboard', () {
      final reader = _FakeReader(const []);
      expect(pickImageFormat(reader), isNull);
    });
  });

  group('mimeForFormat', () {
    test('maps each image format to its MIME', () {
      expect(mimeForFormat(Formats.png), 'image/png');
      expect(mimeForFormat(Formats.jpeg), 'image/jpeg');
      expect(mimeForFormat(Formats.gif), 'image/gif');
      expect(mimeForFormat(Formats.webp), 'image/webp');
      expect(mimeForFormat(Formats.tiff), 'image/tiff');
    });
  });

  group('extensionForFormat', () {
    test('jpeg uses the short jpg form', () {
      expect(extensionForFormat(Formats.jpeg), 'jpg');
    });

    test('maps each image format to its extension', () {
      expect(extensionForFormat(Formats.png), 'png');
      expect(extensionForFormat(Formats.gif), 'gif');
      expect(extensionForFormat(Formats.webp), 'webp');
      expect(extensionForFormat(Formats.tiff), 'tiff');
    });
  });

  group('AttachmentPickError', () {
    test('tooLarge is the only variant (no new error enum added)', () {
      expect(AttachmentPickError.values.length, 1);
      expect(AttachmentPickError.values.single, AttachmentPickError.tooLarge);
    });
  });

  group('PickedAttachment', () {
    test('constructs with the clipboard-image shape', () {
      const a = PickedAttachment(
        fileName: 'clipboard-1.png',
        mime: 'image/png',
        dataBase64: 'AA==',
        thumbnailBase64: null,
      );
      expect(a.fileName, 'clipboard-1.png');
      expect(a.mime, 'image/png');
      expect(a.dataBase64, 'AA==');
      expect(a.thumbnailBase64, isNull);
    });
  });

  // Under `flutter test` there is no platform clipboard, so the read throws
  // the same way a Windows clipboard the process cannot open does. That
  // failure is reported, not thrown: the composer must survive Ctrl+V.
  group('PasteImageAction', () {
    test('a failed clipboard read is reported and does not throw', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final action = PasteImageAction(
        onAttach: (_) => fail('nothing to attach'),
        onAttachmentPickError: (_) => fail('not a size error'),
        gate: () => true,
      );

      await expectLater(
        action.invoke(const PasteTextIntent(SelectionChangedCause.keyboard)),
        completes,
      );

      expect(reported, hasLength(1));
      expect(reported.single.library, 'clipboard_paste_handler');
    });
  });
}
