import 'dart:async' show Completer;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart'
    show ErrorDescription, FlutterError, FlutterErrorDetails;
import 'package:flutter/widgets.dart' show Action, Intent, PasteTextIntent;
import 'package:super_clipboard/super_clipboard.dart';

import 'package:mosh/src/features/shared/attachment_picker.dart';

/// Image formats we accept from the clipboard, in priority order (matches
/// the spec: png, jpeg, gif, webp, tiff). Each is a [FileFormat], read as
/// raw bytes through [readImageBytes].
const List<SimpleFileFormat> _imageFormats = [
  Formats.png,
  Formats.jpeg,
  Formats.gif,
  Formats.webp,
  Formats.tiff,
];

/// Picks the first image format present on [reader], or null when the
/// clipboard holds no image (plain text / uri / etc.). Pure + synchronous so
/// it is unit-testable with a fake reader (no platform channel needed).
SimpleFileFormat? pickImageFormat(ClipboardDataReader reader) {
  for (final format in _imageFormats) {
    if (reader.canProvide(format)) return format;
  }
  return null;
}

/// MIME string for a chosen image format.
String mimeForFormat(SimpleFileFormat format) {
  if (identical(format, Formats.png)) return 'image/png';
  if (identical(format, Formats.jpeg)) return 'image/jpeg';
  if (identical(format, Formats.gif)) return 'image/gif';
  if (identical(format, Formats.webp)) return 'image/webp';
  if (identical(format, Formats.tiff)) return 'image/tiff';
  // Should be unreachable for a format from [_imageFormats]; defensive only.
  return 'application/octet-stream';
}

/// File extension for a chosen image format. JPEG uses `jpg` (the common
/// short form for the synthesized filename).
String extensionForFormat(SimpleFileFormat format) {
  if (identical(format, Formats.png)) return 'png';
  if (identical(format, Formats.jpeg)) return 'jpg';
  if (identical(format, Formats.gif)) return 'gif';
  if (identical(format, Formats.webp)) return 'webp';
  if (identical(format, Formats.tiff)) return 'tiff';
  return 'bin';
}

/// The bytes of [format] on [reader], or null when the clipboard does not
/// offer it after all. Image formats are file formats in super_clipboard,
/// which only exposes them through the callback-shaped `getFile`; this is
/// that call as a Future.
Future<Uint8List?> readImageBytes(
  ClipboardDataReader reader,
  FileFormat format,
) {
  final completer = Completer<Uint8List?>();
  final progress = reader.getFile(
    format,
    (file) async {
      try {
        completer.complete(await file.readAll());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    },
    onError: completer.completeError,
  );
  if (progress == null) return Future.value(null);
  return completer.future;
}

/// Reads the clipboard, and if it holds an image, synthesizes a
/// [PickedAttachment] with original bytes and both JPEG previews and forwards it to
/// [onAttach]. Returns true when an image was attached (the paste is
/// swallowed -- the default text insertion must NOT also run). Returns false
/// when the clipboard holds no image (the caller lets the default text paste
/// proceed).
///
/// [maxBytes] mirrors the shared `AttachmentPicker.maxBytes` ceiling (50 MB).
/// On overflow [onAttachmentPickError] fires with
/// [AttachmentPickError.tooLarge] and the paste is swallowed (same as the
/// paperclip path).
Future<bool> handlePasteImage({
  required AttachmentPickedCallback onAttach,
  required AttachmentPickErrorCallback onAttachmentPickError,
  int maxBytes = 50 * 1024 * 1024,
}) async {
  // No system clipboard (web without the async API) reads as "no image".
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return false;
  final reader = await clipboard.read();
  final format = pickImageFormat(reader);
  if (format == null) return false; // no image -- let text paste proceed
  final bytes = await readImageBytes(reader, format);
  if (bytes == null) return false; // clipboard reported an image but read empty
  if (bytes.length > maxBytes) {
    onAttachmentPickError(AttachmentPickError.tooLarge);
    return true; // swallow the paste (parity with the picker overflow path)
  }
  final ext = extensionForFormat(format);
  final fileName = 'clipboard-${DateTime.now().millisecondsSinceEpoch}.$ext';
  try {
    final picked = await ingestAttachment(
      bytes: bytes,
      fileName: fileName,
      maxBytes: maxBytes,
    );
    if (picked != null) onAttach(picked);
  } on AttachmentPreviewException {
    onAttachmentPickError(AttachmentPickError.previewUnavailable);
  }
  return true;
}

/// An [Action] overriding [PasteTextIntent] for the composer's [TextField].
/// When the clipboard holds an image it attaches it (swallowing the paste);
/// when it does not it forwards to the [callingAction] so the default
/// text-inserting paste runs. `TextField` here has no `onPaste` callback, so
/// paste is intercepted as an [Intent] via an ancestor `Actions` widget (the
/// same pattern `EditableTextState` uses internally via `Action.overridable`,
/// editable_text.dart:5709).
class PasteImageAction extends Action<PasteTextIntent> {
  PasteImageAction({
    required this.onAttach,
    required this.onAttachmentPickError,
    required this.gate,
  });

  final AttachmentPickedCallback onAttach;
  final AttachmentPickErrorCallback onAttachmentPickError;

  /// Whether image attachment is allowed. Otherwise the platform's text
  /// paste still handles the editable draft, including during admission.
  final bool Function() gate;

  @override
  Future<Object?> invoke(PasteTextIntent intent) async {
    // `callingAction` is only set for the synchronous part of this call:
    // the framework clears it as soon as `invoke` returns its Future, so it
    // has to be captured before the first await or text paste never runs.
    final textPaste = callingAction;
    if (!gate()) return textPaste?.invoke(intent);
    bool swallowed;
    try {
      swallowed = await handlePasteImage(
        onAttach: onAttach,
        onAttachmentPickError: onAttachmentPickError,
      );
    } catch (error, stackTrace) {
      // A clipboard the platform refuses to open, or an image that will not
      // decode, must not take the composer down: fall back to text paste.
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'clipboard_paste_handler',
        context: ErrorDescription('while reading an image off the clipboard'),
      ));
      swallowed = false;
    }
    if (swallowed) return null; // image attached -- do NOT also paste text
    // No image on the clipboard -- defer to the default text-inserting paste
    // (EditableTextState._PasteSelectionAction).
    return textPaste?.invoke(intent);
  }
}
