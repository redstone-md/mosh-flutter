// Unit tests for the paste-to-attach decision logic (the pure mappers +
// format picker in clipboard_paste_handler.dart). The platform-channel read
// (`ClipboardReader.readClipboard`) is NOT exercised here -- only the
// synchronous format selection + mime/extension mapping, which is what the
// spec locks in. A fake `ClipboardDataReader` overrides `getFormats` so
// `hasValue` (which delegates to `getFormats`) returns true for the seeded
// formats.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_native_extensions/raw_clipboard.dart' as raw;

import 'package:mosh/src/features/dm/clipboard_paste_handler.dart'
    show
        extensionForFormat,
        mimeForFormat,
        pickImageFormat;
import 'package:mosh/src/features/shared/attachment_picker.dart'
    show AttachmentPickError, PickedAttachment;

/// Minimal fake reader: `hasValue` delegates to `getFormats`, so seeding the
/// format list controls which `pickImageFormat` branch fires. The other
/// abstract members throw `UnimplementedError` -- the picker never calls them.
class _FakeReader extends ClipboardDataReader {
  _FakeReader(this.formats);
  final List<DataFormat> formats;

  @override
  List<DataFormat> getFormats(List<DataFormat> allFormats) =>
      allFormats.where(formats.contains).toList();

  @override
  bool isSynthetized(DataFormat format) => throw UnimplementedError();
  @override
  bool isVirtual(DataFormat format) => throw UnimplementedError();
  @override
  Future<raw.VirtualFileReceiver?> getVirtualFileReceiver(
          {VirtualFileFormat? format}) =>
      throw UnimplementedError();
  @override
  Future<String?> getSuggestedName() => throw UnimplementedError();
  @override
  raw.ReadProgress? getValue<T extends Object>(
          DataFormat<T> format, ValueChanged<DataReaderValue<T>> onValue) =>
      throw UnimplementedError();
  @override
  Future<T?> readValue<T extends Object>(DataFormat<T> format) =>
      throw UnimplementedError();
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
}
 
