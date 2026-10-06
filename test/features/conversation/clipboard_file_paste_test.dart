// IVO-28: Ctrl+V / Cmd+V / the context menu's Paste attach a file copied in
// a file manager through the shared ingest, and still paste plain text.
// A fake `ClipboardDataReader` stands in for the platform clipboard; the
// copied files are real files in a temp directory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:super_clipboard/super_clipboard.dart';

import 'package:mosh/src/features/conversation/clipboard_paste_handler.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';

/// Answers from the seeded formats. [file] is what a file manager put on
/// the clipboard; [gate] holds the read back until a test releases it.
/// Image reads go through `noSuchMethod`, so a test fails if they run.
class _FakeReader implements ClipboardDataReader {
  _FakeReader(this.formats, {this.file, this.gate});
  final List<DataFormat> formats;
  final Uri? file;
  final Future<void>? gate;

  @override
  bool canProvide(DataFormat format) => formats.contains(format);

  @override
  List<DataFormat> getFormats(List<DataFormat> allFormats) =>
      allFormats.where(formats.contains).toList();

  @override
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) async {
    await gate;
    return identical(format, Formats.fileUri) ? file as T? : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

_FakeReader _copied(File file) =>
    _FakeReader(const [Formats.fileUri, Formats.plainText], file: file.uri);

class _Outcome {
  final attached = <PickedAttachment>[];
  final errors = <AttachmentPickError>[];

  Future<bool> paste(ClipboardDataReader reader, {int? maxBytes}) =>
      pasteAttachment(reader,
          onAttach: attached.add,
          onAttachmentPickError: errors.add,
          maxBytes: maxBytes ?? 50 * 1024 * 1024);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('mosh-paste-'));
  tearDown(() => dir.deleteSync(recursive: true));

  File write(String name, List<int> bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(bytes);

  test('a copied file attaches with its name, type and content', () async {
    final file = write('Отчёт 2026.pdf', utf8.encode('%PDF-1.7 report'));
    final outcome = _Outcome();

    expect(await outcome.paste(_copied(file)), isTrue);

    final picked = outcome.attached.single;
    expect(picked.fileName, 'Отчёт 2026.pdf');
    expect(picked.mime, 'application/pdf');
    expect(base64Decode(picked.dataBase64), file.readAsBytesSync());
    expect(picked.thumbnailBase64, isNull);
    expect(outcome.errors, isEmpty);
  });

  test('a copied image file gets both previews, not its Finder icon', () async {
    final file =
        write('photo.png', img.encodePng(img.Image(width: 64, height: 48)));
    final outcome = _Outcome();
    // Finder adds the file icon as TIFF; reading it would hit noSuchMethod.
    final reader =
        _FakeReader(const [Formats.fileUri, Formats.tiff], file: file.uri);

    expect(await outcome.paste(reader), isTrue);

    final picked = outcome.attached.single;
    expect(picked.mime, 'image/png');
    expect(picked.thumbnailBase64, isNotNull);
    expect(picked.previewBase64, isNotNull);
  });

  test('a copied image that will not decode reports the preview error',
      () async {
    final file = write('broken.png', utf8.encode('not a png'));
    final outcome = _Outcome();

    expect(await outcome.paste(_copied(file)), isTrue);

    expect(outcome.attached, isEmpty);
    expect(outcome.errors, [AttachmentPickError.previewUnavailable]);
  });

  test('an oversized copied file is refused with the size error', () async {
    final file = write('big.bin', List.filled(2048, 7));
    final outcome = _Outcome();

    expect(await outcome.paste(_copied(file), maxBytes: 1024), isTrue);

    expect(outcome.attached, isEmpty);
    expect(outcome.errors, [AttachmentPickError.tooLarge]);
  });

  test('a folder or a missing file is reported and attaches nothing', () async {
    final folder = _Outcome();
    expect(await folder.paste(_copied(File(dir.path))), isTrue);
    expect(folder.errors, [AttachmentPickError.notAFile]);

    final missing = _Outcome();
    expect(await missing.paste(_copied(File('${dir.path}/gone.txt'))), isTrue);
    expect(missing.errors, [AttachmentPickError.unreadable]);

    expect([...folder.attached, ...missing.attached], isEmpty);
  });

  test('plain text and web links stay a text paste', () async {
    final outcome = _Outcome();
    expect(
        await outcome.paste(_FakeReader(const [Formats.plainText])), isFalse);
    final web = _FakeReader(const [Formats.fileUri],
        file: Uri.parse('https://example.com/a.png'));
    expect(await outcome.paste(web), isFalse);
    expect(outcome.attached, isEmpty);
    expect(outcome.errors, isEmpty);
  });

  test('a repeated paste during a read attaches the file once', () async {
    final file = write('notes.txt', utf8.encode('hello'));
    final release = Completer<void>();
    final outcome = _Outcome();
    var textPastes = 0;
    final action = PasteAttachmentAction(
      onAttach: outcome.attached.add,
      onAttachmentPickError: outcome.errors.add,
      gate: () => true,
      readClipboard: () async => _FakeReader(const [Formats.fileUri],
          file: file.uri, gate: release.future),
    );
    Future<Object?> text() async => textPastes++;

    final first = action.paste(text);
    await action.paste(text);
    release.complete();
    await first;

    expect(outcome.attached, hasLength(1));
    expect(textPastes, 0);
  });

  testWidgets('the context menu Paste attaches a copied file, else pastes text',
      (tester) async {
    final file = write('notes.txt', utf8.encode('hello'));
    final messenger = tester.binding.defaultBinaryMessenger;
    // The composer creates its voice recorder on mount.
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (call) async => null);
    messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => switch (call.method) {
              'Clipboard.hasStrings' => {'value': true},
              'Clipboard.getData' => {'text': 'pasted'},
              _ => null,
            });
    final attached = <PickedAttachment>[];
    var reader = _copied(file);
    final draft = TextEditingController(text: 'draft ');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationComposer(
          controller: draft,
          sending: false,
          placeholder: 'p',
          sendLabel: 'Send',
          onSend: () {},
          attachLabel: 'a',
          onAttach: attached.add,
          onAttachmentPickError: (_) => fail('nothing to report'),
          voiceRecordLabel: 'r',
          voiceDiscardLabel: 'd',
          voiceStopLabel: 's',
          voicePlayLabel: 'pl',
          voiceSendLabel: 'vs',
          voicePermissionDeniedLabel: 'denied',
          onSendVoice: (_) {},
          onVoiceError: (_) {},
          inputDeviceId: () => null,
          readClipboard: () async => reader,
        ),
      ),
    ));

    // The paste reads a real file, so it needs real event-loop turns.
    Future<void> pasteFromMenu(bool Function() done) async {
      await tester.longPress(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste'));
      for (var i = 0; i < 100 && !done(); i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    await pasteFromMenu(() => attached.isNotEmpty);
    expect(attached.single.fileName, 'notes.txt');
    expect(draft.text, 'draft ');

    reader = _FakeReader(const [Formats.plainText]);
    await pasteFromMenu(() => draft.text != 'draft ');
    expect(attached, hasLength(1));
    expect('pasted'.allMatches(draft.text), hasLength(1));
  });
}
