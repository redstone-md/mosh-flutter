import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Supplies native picker results without opening a desktop dialog.
class TestFilePicker extends FilePickerPlatform {
  TestFilePicker(this.bytes);
  final Uint8List bytes;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
    AndroidSAFOptions? androidSafOptions,
  }) async =>
      FilePickerResult([
        PlatformFile(name: 'screenshot.png', size: bytes.length, bytes: bytes)
      ]);
}
