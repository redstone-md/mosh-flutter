/// Paste-to-attach clipboard image -- the 1-в-1 port of React
/// ChatComposer.tsx:71-82 `handlePaste`. React intercepts the input's paste
/// event, finds the first clipboard item with `kind === "file"`, calls
/// `event.preventDefault()`, and forwards the file to `onAttach(file)`. This
/// Dart port does the same via `super_clipboard`: when the composer has focus
/// and the system clipboard holds an image (png/jpeg/gif/webp/tiff), synthesize
/// a [PickedAttachment] and forward it to the composer's existing `onAttach`.
/// Plain-text pastes fall through to the default text insertion (React parity:
/// only file items are forwarded; text pastes normally).
///
/// Interception point: Flutter 3.44 `TextField` has NO `onPaste` callback
/// (neither `bool Function()?` nor a `TextEditablePasteState` variant exists
/// in this SDK). Paste is dispatched as a [PasteTextIntent] via
/// `DefaultTextEditingShortcuts` (Ctrl/Cmd+V, Shift+Insert) and handled by an
/// overridable `Action` registered on the `EditableTextState`
/// (`Action.overridable`, editable_text.dart:5709). An ancestor `Actions`
/// widget mapping `PasteTextIntent` -> a custom [Action] fully intercepts
/// the intent: `_visitActionsAncestors` stops at the first matching ancestor,
/// so the default text-inserting action runs ONLY if the override calls
/// `callingAction?.invoke(...)` -- the Dart equivalent of React's
/// `event.preventDefault()`.
library;

import 'dart:async' show Completer;
import 'dart:convert' show base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart'
    show ErrorDescription, FlutterError, FlutterErrorDetails;
import 'package:flutter/widgets.dart' show Action, Intent, PasteTextIntent;
import 'package:super_clipboard/super_clipboard.dart';

import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/thumbnail.dart' show createThumbnail;

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

/// MIME string for a chosen image format (1-в-1 with the React `file.type`).
String mimeForFormat(SimpleFileFormat format) {
  if (identical(format, Formats.png)) return 'image/png';
  if (identical(format, Formats.jpeg)) return 'image/jpeg';
  if (identical(format, Formats.gif)) return 'image/gif';
  if (identical(format, Formats.webp)) return 'image/webp';
  if (identical(format, Formats.tiff)) return 'image/tiff';
  // Should be unreachable for a format from [_imageFormats]; defensive only.
  return 'application/octet-stream';
}

/// File extension for a chosen image format. JPEG uses `jpg` (React parity:
/// the synthesized filename uses the common short form).
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
/// [PickedAttachment] (base64 bytes + 320px JPEG thumbnail) and forwards it to
/// [onAttach]. Returns true when an image was attached (the paste is
/// swallowed -- the default text insertion must NOT also run, mirroring
/// React's `event.preventDefault()`). Returns false when the clipboard holds
/// no image (the caller lets the default text paste proceed).
///
/// [maxBytes] mirrors the shared `AttachmentPicker.maxBytes` ceiling (50 MB).
/// On overflow [onAttachmentPickError] fires with
/// [AttachmentPickError.tooLarge] and the paste is swallowed (parity with the
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
  final mime = mimeForFormat(format);
  final fileName = 'clipboard-${DateTime.now().millisecondsSinceEpoch}.$ext';
  final thumbnail = await createThumbnail(bytes, fileName);
  onAttach(PickedAttachment(
    fileName: fileName,
    mime: mime,
    dataBase64: base64Encode(bytes),
    thumbnailBase64: thumbnail,
  ));
  return true;
}

/// An [Action] overriding [PasteTextIntent] for the composer's [TextField].
/// When the clipboard holds an image it attaches it (swallowing the paste);
/// when it does not it forwards to the [callingAction] so the default
/// text-inserting paste runs. This is the Flutter 3.44 analogue of React's
/// `ChatComposer.tsx:71-82` `handlePaste` + `event.preventDefault()`:
/// `TextField` here has no `onPaste` callback, so paste is intercepted as an
/// [Intent] via an ancestor `Actions` widget (the same pattern
/// `EditableTextState` uses internally via `Action.overridable`,
/// editable_text.dart:5709).
class PasteImageAction extends Action<PasteTextIntent> {
  PasteImageAction({
    required this.onAttach,
    required this.onAttachmentPickError,
    required this.gate,
  });

  final AttachmentPickedCallback onAttach;
  final AttachmentPickErrorCallback onAttachmentPickError;

  /// Returns true when the composer accepts input (not sending + not
  /// disabled); the paste handler is skipped otherwise so a paste into a
  /// locked composer falls back to the platform default (no-op).
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
    // (EditableTextState._PasteSelectionAction), parity with React forwarding
    // only `kind === "file"` items and letting plain text paste normally.
    return textPaste?.invoke(intent);
  }
}
