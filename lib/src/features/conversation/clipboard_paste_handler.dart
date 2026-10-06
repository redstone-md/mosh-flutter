import 'dart:async' show Completer;
import 'dart:io'
    show File, FileSystemEntity, FileSystemEntityType, FileSystemException;
import 'dart:typed_data' show BytesBuilder, Uint8List;

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

/// Reads the system clipboard, or null where there is none (web without the
/// async API). The paste action takes this as a parameter so tests can hand
/// it a fake reader.
Future<ClipboardDataReader?> readSystemClipboard() async =>
    SystemClipboard.instance?.read();

/// The first local file a file manager copied, or null. Checked before
/// images: Finder also puts the file's icon on the clipboard as TIFF.
Future<Uri?> readCopiedFile(ClipboardDataReader reader) async {
  if (!reader.canProvide(Formats.fileUri)) return null;
  final uri = await reader.readValue(Formats.fileUri);
  return uri != null && uri.isScheme('file') ? uri : null;
}

/// Attaches the copied file at [uri] through the shared ingest, or reports
/// why it cannot: a directory, a missing or unreadable file, or one over
/// [maxBytes]. The file is read whole before anything is attached.
Future<void> attachCopiedFile(
  Uri uri, {
  required AttachmentPickedCallback onAttach,
  required AttachmentPickErrorCallback onAttachmentPickError,
  required int maxBytes,
}) async {
  final file = File.fromUri(uri);
  final Uint8List bytes;
  try {
    final type = await FileSystemEntity.type(file.path);
    if (type != FileSystemEntityType.file) {
      return onAttachmentPickError(type == FileSystemEntityType.directory
          ? AttachmentPickError.notAFile
          : AttachmentPickError.unreadable);
    }
    // Streamed with a running limit: a file that grows while being read is
    // refused without loading more than [maxBytes] plus one chunk.
    final read = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      read.add(chunk);
      if (read.length > maxBytes) {
        return onAttachmentPickError(AttachmentPickError.tooLarge);
      }
    }
    bytes = read.takeBytes();
  } on FileSystemException {
    return onAttachmentPickError(AttachmentPickError.unreadable);
  }
  await _ingest(bytes, uri.pathSegments.last,
      onAttach: onAttach,
      onAttachmentPickError: onAttachmentPickError,
      maxBytes: maxBytes);
}

Future<void> _ingest(
  Uint8List bytes,
  String fileName, {
  required AttachmentPickedCallback onAttach,
  required AttachmentPickErrorCallback onAttachmentPickError,
  required int maxBytes,
}) async {
  try {
    final picked = await ingestAttachment(
        bytes: bytes, fileName: fileName, maxBytes: maxBytes);
    if (picked == null) {
      onAttachmentPickError(AttachmentPickError.tooLarge);
    } else {
      onAttach(picked);
    }
  } on AttachmentPreviewException {
    onAttachmentPickError(AttachmentPickError.previewUnavailable);
  }
}

/// Attaches a copied file, else a copied image, from [reader]. Returns true
/// when the paste is consumed (attached or reported) so the default text
/// insertion must NOT also run, and false when the clipboard holds neither
/// (the caller lets the text paste proceed).
///
/// [maxBytes] mirrors the shared `AttachmentPicker.maxBytes` ceiling (50 MB).
/// On overflow [onAttachmentPickError] fires with
/// [AttachmentPickError.tooLarge] and the paste is swallowed (same as the
/// paperclip path).
Future<bool> pasteAttachment(
  ClipboardDataReader reader, {
  required AttachmentPickedCallback onAttach,
  required AttachmentPickErrorCallback onAttachmentPickError,
  int maxBytes = 50 * 1024 * 1024,
}) async {
  final file = await readCopiedFile(reader);
  if (file != null) {
    await attachCopiedFile(file,
        onAttach: onAttach,
        onAttachmentPickError: onAttachmentPickError,
        maxBytes: maxBytes);
    return true;
  }
  final format = pickImageFormat(reader);
  if (format == null) return false; // no image -- let text paste proceed
  final bytes = await readImageBytes(reader, format);
  if (bytes == null) return false; // clipboard reported an image but read empty
  final ext = extensionForFormat(format);
  final fileName = 'clipboard-${DateTime.now().millisecondsSinceEpoch}.$ext';
  await _ingest(bytes, fileName,
      onAttach: onAttach,
      onAttachmentPickError: onAttachmentPickError,
      maxBytes: maxBytes);
  return true;
}

/// An [Action] overriding [PasteTextIntent] for the composer's [TextField].
/// When the clipboard holds a file or an image it attaches it (swallowing
/// the paste); otherwise it forwards to the [callingAction] so the default
/// text-inserting paste runs. `TextField` here has no `onPaste` callback, so
/// paste is intercepted as an [Intent] via an ancestor `Actions` widget (the
/// same pattern `EditableTextState` uses internally via `Action.overridable`,
/// editable_text.dart:5709). The context menu's Paste calls [paste] directly.
class PasteAttachmentAction extends Action<PasteTextIntent> {
  PasteAttachmentAction({
    required this.onAttach,
    required this.onAttachmentPickError,
    required this.gate,
    this.readClipboard = readSystemClipboard,
  });

  final AttachmentPickedCallback onAttach;
  final AttachmentPickErrorCallback onAttachmentPickError;

  /// Whether attaching is allowed. Otherwise the platform's text paste
  /// still handles the editable draft, including during admission.
  final bool Function() gate;
  final Future<ClipboardDataReader?> Function() readClipboard;

  /// Shared across rebuilds: a held or repeated Ctrl+V must not attach the
  /// same file twice while the first paste is still reading it.
  static bool _inFlight = false;

  @override
  Future<Object?> invoke(PasteTextIntent intent) {
    // `callingAction` is only set for the synchronous part of this call:
    // the framework clears it as soon as `invoke` returns its Future, so it
    // has to be captured before the first await or text paste never runs.
    final textPaste = callingAction;
    return paste(() async => textPaste?.invoke(intent));
  }

  /// Attaches from the clipboard, or runs [textPaste] when it holds no file
  /// or image, attaching is gated off, or the clipboard cannot be read.
  Future<Object?> paste(Future<Object?> Function() textPaste) async {
    if (!gate()) return textPaste();
    if (_inFlight) return null; // the running paste owns this clipboard
    _inFlight = true;
    bool swallowed;
    try {
      final reader = await readClipboard();
      swallowed = reader != null &&
          await pasteAttachment(reader,
              onAttach: onAttach, onAttachmentPickError: onAttachmentPickError);
    } catch (error, stackTrace) {
      // A clipboard the platform refuses to open, or an image that will not
      // decode, must not take the composer down: fall back to text paste.
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'clipboard_paste_handler',
        context: ErrorDescription('while reading the clipboard to attach'),
      ));
      swallowed = false;
    } finally {
      _inFlight = false;
    }
    // Attached -- do NOT also paste text. Otherwise defer to the default
    // text-inserting paste (EditableTextState._PasteSelectionAction).
    return swallowed ? null : textPaste();
  }
}
