// Shared AttachmentPicker -- the 1-в-1 port of React's
// `src/features/private-dm/AttachmentPicker.tsx`. A paperclip IconButton that
// opens the native file picker (file_picker `FilePicker.pickFile`), reads the
// picked file's bytes via `PlatformFile.readAsBytes()`, infers the MIME type
// from the extension (`package:mime lookupMimeType`, since file_picker does
// not expose a MIME like the browser `File.type`), enforces the 50 MB
// ceiling (React `isAttachmentTooLarge` / `ATTACHMENT_MAX_BYTES`), and hands a
// ready-to-send [PickedAttachment] to the composer via `onPick`.
//
// React structure (AttachmentPicker.tsx): a hidden `<input type=file>` plus a
// paperclip button (`IconPaperclip size=16`). On click the input opens; on
// change the first file is passed to `onPick(file)` and the input resets.
// `disabled` gates both the button and the input.
//
// Flutter port: there is no hidden input to coordinate -- `FilePicker.pickFile`
// opens the native picker directly from the button's `onPressed`. The button
// is a plain `IconButton` (React `<button class=composer-attach>`) with
// `Icons.attach_file` (the Material paperclip -- closest to Tabler's
// `IconPaperclip`). `tooltip` mirrors React's `aria-label`/`title`. `onPressed`
// is null when `disabled` (mirrors React's `disabled` attr). When the picker is
// cancelled or returns no file, nothing happens (mirrors React's `if (file)
// onPick(file)`).
//
// Voice + ChatDropZone are SEPARATE concerns (ChatComposer.tsx): voice is its
// own VoiceComposer widget (a later atomic), and ChatDropZone is a drag-drop
// wrapper that also calls `onAttach`. This widget is JUST the paperclip path.
//
// 50 MB ceiling: React `isAttachmentTooLarge` rejects `file.size >
// ATTACHMENT_MAX_BYTES` (50 * 1024 * 1024). The picker mirrors that BEFORE
// reading bytes (so a 500 MB file is rejected without loading it into RAM).
// On overflow `onError(AttachmentTooLarge)` fires so the screen surfaces the
// localized limit message (the composer does not hard-code the message).
library;

import 'dart:convert' show base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart' show lookupMimeType;

import 'package:mosh/src/features/shared/thumbnail.dart' show createThumbnail;

/// Why the picker rejected the picked file. Maps to the localized message the
/// screen shows (mirrors React's single `onError("Attachment exceeds the 50
/// MB limit")` path -- the enum leaves room for future reasons without an API
/// churn).
enum AttachmentPickError { tooLarge }

/// A picked file ready to send: the bytes already base64-encoded (the gateway
/// `Gateway.sendAttachment` `dataBase64` arg) plus the
/// `fileName` and inferred `mime`. `thumbnailBase64` is the base64 of a
/// 320px JPEG preview for image picks (1-в-1 with React `createThumbnail`);
/// null for non-images or decode failures (never fatal -- mirrors React).
class PickedAttachment {
  const PickedAttachment({
    required this.fileName,
    required this.mime,
    required this.dataBase64,
    this.thumbnailBase64,
  });

  final String fileName;
  final String mime;
  final String dataBase64;
  final String? thumbnailBase64;
}

typedef AttachmentPickedCallback = void Function(PickedAttachment attachment);
typedef AttachmentPickErrorCallback = void Function(AttachmentPickError error);

/// Shared byte->PickedAttachment ingest path. Both the paperclip picker and
/// [ChatDropZone] route through this (DRY): infer MIME via `package:mime`
/// (file_picker / desktop_drop expose no MIME unlike the browser `File.type`),
/// generate the 320px image/video thumbnail (1-в-1 with React
/// `createThumbnail`), and base64-encode the payload. Returns null when the
/// payload exceeds [maxBytes]; the caller decides whether to surface
/// [AttachmentPickError.tooLarge] -- keeps the helper pure so the picker keeps
/// its pre-read rejection (500 MB files never load into RAM) and the drop
/// zone fires its own onError.
///
/// Mirrors React sendAttachment (use-chat-orchestration.ts L177):
/// `const thumbnail = await createThumbnail(file)`.
Future<PickedAttachment?> ingestAttachment({
  required Uint8List bytes,
  required String fileName,
  required int maxBytes,
}) async {
  if (bytes.length > maxBytes) return null;
  final mime = lookupMimeType(fileName) ?? '';
  final thumbnail = await createThumbnail(bytes, fileName);
  return PickedAttachment(
    fileName: fileName,
    mime: mime,
    dataBase64: base64Encode(bytes),
    thumbnailBase64: thumbnail,
  );
}

/// Paperclip button that opens the native file picker and produces a
/// [PickedAttachment] (or rejects with [AttachmentPickError]).
///
/// Stateless because the picker state is transient (open -> read -> hand off);
/// the screen owns the `sending` flag + the post-send invalidate. The
/// `disabled` prop mirrors React's `disabled` (gated while a send is in
/// flight).
class AttachmentPicker extends StatelessWidget {
  const AttachmentPicker({
    super.key,
    required this.disabled,
    required this.ariaLabel,
    required this.onPick,
    required this.onError,
    this.maxBytes = 50 * 1024 * 1024,
  });

  final bool disabled;
  final String ariaLabel;
  final AttachmentPickedCallback onPick;
  final AttachmentPickErrorCallback onError;
  final int maxBytes;

  Future<void> _pick() async {
    final result = await FilePicker.pickFile(
      type: FileType.any,
      dialogTitle: ariaLabel,
    );
    if (result == null) return; // cancelled
    // Reject before reading bytes -- a 500 MB file is rejected without
    // loading it into RAM (file_picker exposes `result.size` pre-read).
    if (result.size > maxBytes) {
      onError(AttachmentPickError.tooLarge);
      return;
    }
    final bytes = await result.readAsBytes();
    final picked = await ingestAttachment(
      bytes: bytes,
      fileName: result.name,
      maxBytes: maxBytes,
    );
    // The pre-read size check above guarantees picked != null here; the
    // null branch is defensive against a picker that lies about size.
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.attach_file, size: 18),
      tooltip: ariaLabel,
      onPressed: disabled ? null : _pick,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      visualDensity: VisualDensity.compact,
    );
  }
}
