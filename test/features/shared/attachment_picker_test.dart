import 'dart:async' show Completer;
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/src/features/shared/attachment_picker.dart';

import '../../support/file_picker.dart';
import '../../support/pump.dart';

void main() {
  testWidgets(
      'the paperclip forwards both previews and unchanged original bytes',
      (tester) async {
    final previous = FilePickerPlatform.instance;
    addTearDown(() => FilePickerPlatform.instance = previous);
    final bytes =
        Uint8List.fromList(img.encodePng(img.Image(width: 640, height: 480)));
    FilePickerPlatform.instance = TestFilePicker(bytes);
    PickedAttachment? picked;
    late final Completer<void> completed;
    await pumpScreen(
        tester,
        Scaffold(
            body: AttachmentPicker(
          disabled: false,
          ariaLabel: 'Attach',
          onPick: (value) {
            picked = value;
            completed.complete();
          },
          onError: (_) {
            completed.complete();
            fail('valid image rejected');
          },
        )));
    await tester.runAsync(() async {
      completed = Completer<void>();
      await tester.tap(find.byIcon(Icons.attach_file));
      // test-policy: timeout https://github.com/redstone-md/mosh-flutter/issues/56 -- retain the previous 2s ingest callback bound without polling
      await completed.future.timeout(const Duration(seconds: 2));
    });
    expect(picked, isNotNull);
    expect(base64Decode(picked!.dataBase64), bytes);
    expect(picked!.thumbnailBase64!.length, lessThanOrEqualTo(2048));
    expect(img.decodeJpg(base64Decode(picked!.previewBase64!))!.width, 320);
  });

  testWidgets('the paperclip reports a bad preview and never sends the image',
      (tester) async {
    final previous = FilePickerPlatform.instance;
    addTearDown(() => FilePickerPlatform.instance = previous);
    FilePickerPlatform.instance = TestFilePicker(Uint8List.fromList([1, 2, 3]));
    AttachmentPickError? error;
    late final Completer<void> completed;
    await pumpScreen(
        tester,
        Scaffold(
            body: AttachmentPicker(
          disabled: false,
          ariaLabel: 'Attach',
          onPick: (_) {
            completed.complete();
            fail('unreadable image sent');
          },
          onError: (value) {
            error = value;
            completed.complete();
          },
        )));
    await tester.runAsync(() async {
      completed = Completer<void>();
      await tester.tap(find.byIcon(Icons.attach_file));
      // test-policy: timeout https://github.com/redstone-md/mosh-flutter/issues/56 -- retain the previous 2s ingest callback bound without polling
      await completed.future.timeout(const Duration(seconds: 2));
    });
    expect(error, AttachmentPickError.previewUnavailable);
    expect(tester.takeException(), isNull);
  });
}
