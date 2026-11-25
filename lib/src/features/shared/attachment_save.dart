import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';

/// Asks where a copy of a file goes and writes it there. Answers the place,
/// or null when the dialog was dismissed. Injectable, so a widget test
/// records the copy instead of opening the system's dialog.
typedef AttachmentSaver = Future<String?> Function(
    {required String fileName, required Uint8List bytes});

final attachmentSaverProvider = Provider<AttachmentSaver>(
  (_) => ({required fileName, required bytes}) =>
      FilePicker.saveFile(fileName: fileName, bytes: bytes),
);

/// Saves a copy of the attachment at [localPath] where the user says, under
/// [fileName], and tells how it went. A dismissed dialog says nothing.
/// An attachment is 50 MB at most, so it is read whole.
Future<void> saveAttachmentAs({
  required AttachmentSaver saver,
  required Toaster toaster,
  required AppLocalizations l,
  required String localPath,
  required String fileName,
}) async {
  try {
    final bytes = await File(localPath).readAsBytes();
    final saved = await saver(fileName: fileName, bytes: bytes);
    if (saved != null) {
      toaster.show(l.mediaViewerSaved, kind: ToastKind.success);
    }
  } catch (_) {
    toaster.show(l.mediaViewerSaveFailed, kind: ToastKind.error);
  }
}
