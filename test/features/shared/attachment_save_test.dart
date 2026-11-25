// Saving a copy of an attachment: the file goes to the system's save dialog
// whole and under its own name, and the toast tells how it went.
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/attachment_save.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';

void main() {
  late Directory dir;
  late Toaster toaster;
  late AppLocalizations l;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mosh-save');
    toaster = Toaster();
    l = await AppLocalizations.delegate.load(const Locale('en'));
  });
  tearDown(() {
    toaster.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<List<(String, ToastKind)>> save(AttachmentSaver saver,
      {String file = 'notes.txt'}) async {
    await saveAttachmentAs(
        saver: saver,
        toaster: toaster,
        l: l,
        localPath: '${dir.path}/$file',
        fileName: 'notes.txt');
    return [for (final t in toaster.toasts) (t.message, t.kind)];
  }

  test('the copy is the whole file under its own name', () async {
    File('${dir.path}/notes.txt').writeAsStringSync('hello');
    final asked = <(String, String)>[];

    final told = await save(({required fileName, required bytes}) async {
      asked.add((fileName, String.fromCharCodes(bytes)));
      return '/home/maya/notes.txt';
    });

    expect(asked, [('notes.txt', 'hello')]);
    expect(told, [('File saved', ToastKind.success)]);
  });

  test('a dismissed save dialog says nothing', () async {
    File('${dir.path}/notes.txt').writeAsStringSync('hello');

    expect(await save(({required fileName, required bytes}) async => null),
        isEmpty);
  });

  test('a copy that cannot be written is told as an error', () async {
    File('${dir.path}/notes.txt').writeAsStringSync('hello');

    final told = await save(({required fileName, required bytes}) async =>
        throw const FileSystemException('disk full'));

    expect(told, [('Could not save the file', ToastKind.error)]);
  });

  test('a file that is gone from the device is told as an error', () async {
    final told = await save(
        ({required fileName, required bytes}) async => '/unused',
        file: 'gone.txt');

    expect(told, [('Could not save the file', ToastKind.error)]);
  });
}
