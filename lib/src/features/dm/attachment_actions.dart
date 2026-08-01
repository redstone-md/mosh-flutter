// Attachment actions row, ported 1:1 from React's
// `<div className="attachment-actions">` (src/features/private-dm/AttachmentCard.tsx).
// Extracted out of attachment_card.dart to keep that file under the 500-line
// ceiling; the card's file/media branches still compose [AttachmentActions]
// to the right of the shared name + meta + progress bar. The 4-state machine
// (available/!outgoing offered|cancelled/failed/downloading) and the empty
// `SizedBox.shrink` fallback are preserved exactly -- do NOT simplify.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// The ACTIONS ROW, ported 1:1 from React's `<div className="attachment-actions">`.
/// At most ONE `IconButton` renders, gated on `state` + `outgoing` (the
/// outgoing sender only ever gets Open):
///   - available              -> Open (Icons.open_in_new), disabled when
///                               `view.localPath == null` (React
///                               `disabled={!view?.local_path}`).
///   - !outgoing && offered   -> Download (Icons.download).
///   - !outgoing && cancelled -> Retry-download (Icons.download, the same
///                               button with the "Retry download" label).
///   - !outgoing && failed    -> Retry (Icons.refresh).
///   - !outgoing && downloading -> Cancel (Icons.close).
/// Download/Retry are disabled when `busy` (React `attachments.busy`);
/// Cancel is always enabled (React has no `disabled` guard on cancel).
/// Each button's `Semantics(label:)` carries the React `aria-label`
/// (interpolates the file name) and `IconButton.tooltip` carries the React
/// `title` (short label). Compact density + small `splashRadius` match
/// React's `btn-icon` sizing.
class AttachmentActions extends StatelessWidget {
  const AttachmentActions({
    super.key,
    required this.descriptor,
    required this.view,
    required this.state,
    required this.outgoing,
    required this.busy,
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
    required this.l,
  });

  final AttachmentDescriptor descriptor;
  final AttachmentView? view;
  final AttachmentState state;
  final bool outgoing;
  final bool busy;
  final void Function(String attachmentId) onDownload;
  final void Function(String attachmentId) onCancel;
  final void Function(AttachmentDescriptor descriptor) onOpen;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final fileName = descriptor.fileName;
    final id = descriptor.attachmentId;
    final localPath = view?.localPath;

    // 1) available -> Open (disabled when no localPath).
    if (state == AttachmentState.available) {
      final onPressed = localPath == null ? null : () => onOpen(descriptor);
      return _ActionIcon(
        icon: Icons.open_in_new,
        tooltip: l.attachmentOpen,
        semanticsLabel: l.attachmentOpenAria(fileName),
        onPressed: onPressed,
      );
    }

    // 2) !outgoing && (offered|cancelled) -> Download / Retry-download
    //    (cancelled reuses the button with the "Retry download" label).
    if (!outgoing &&
        (state == AttachmentState.offered || state == AttachmentState.cancelled)) {
      final isRetry = state == AttachmentState.cancelled;
      final tooltip = isRetry ? l.attachmentRetryDownload : l.attachmentDownload;
      final semanticsLabel = isRetry
          ? l.attachmentRetryDownloadAria(fileName)
          : l.attachmentDownloadAria(fileName);
      return _ActionIcon(
        icon: Icons.download,
        tooltip: tooltip,
        semanticsLabel: semanticsLabel,
        onPressed: busy ? null : () => onDownload(id),
        busy: busy,
      );
    }

    // 3) !outgoing && failed -> Retry.
    if (!outgoing && state == AttachmentState.failed) {
      return _ActionIcon(
        icon: Icons.refresh,
        tooltip: l.attachmentRetry,
        semanticsLabel: l.attachmentRetryAria(fileName),
        onPressed: busy ? null : () => onDownload(id),
        busy: busy,
      );
    }

    // 4) !outgoing && downloading -> Cancel (always enabled).
    if (!outgoing && state == AttachmentState.downloading) {
      return _ActionIcon(
        icon: Icons.close,
        tooltip: l.attachmentCancelDownload,
        semanticsLabel: l.attachmentCancelDownloadAria(fileName),
        onPressed: () => onCancel(id),
      );
    }

    // No action button (e.g. outgoing sender in a non-available state):
    // an empty SizedBox.shrink so the parent Row reserves no gap.
    return const SizedBox.shrink();
  }
}

/// One compact action button. Wraps `IconButton` in a `Semantics` with the
/// full aria-label (file name interpolated); `IconButton.tooltip` carries
/// the short title. `busy` toggles `Semantics(enabled: !busy)` so screen
/// readers announce the disabled state (React's `aria-busy`).
class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.semanticsLabel,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final String semanticsLabel;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: onPressed != null && !busy,
      child: IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        splashRadius: 16,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
