// Transfer controls for file and media cards. Available files open from
// the card itself; this row only downloads, retries or cancels a transfer.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';

/// The actions row. At most ONE `IconButton` renders, gated on `state` +
/// `outgoing` (outgoing and available files have no transfer button):
///   - !outgoing && offered   -> Download (Icons.download).
///   - !outgoing && cancelled -> Retry-download (Icons.download, the same
///                               button with the "Retry download" label).
///   - !outgoing && failed    -> Retry (Icons.refresh).
///   - !outgoing && downloading -> Cancel (Icons.close).
/// Download/Retry are disabled when `busy`; Cancel is always enabled.
/// Each button's `Semantics(label:)` carries the full accessible label
/// (interpolates the file name) and `IconButton.tooltip` carries the short
/// label. Compact density + small `splashRadius` keep the row dense.
class AttachmentActions extends StatelessWidget {
  const AttachmentActions({
    super.key,
    required this.descriptor,
    required this.state,
    required this.outgoing,
    required this.busy,
    required this.onDownload,
    required this.onCancel,
    required this.l,
  });

  final AttachmentDescriptor descriptor;
  final AttachmentState state;
  final bool outgoing;
  final bool busy;
  final void Function(String attachmentId) onDownload;
  final void Function(String attachmentId) onCancel;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final fileName = descriptor.fileName;
    final id = descriptor.attachmentId;
    // 2) !outgoing && (offered|cancelled) -> Download / Retry-download
    //    (cancelled reuses the button with the "Retry download" label).
    if (!outgoing &&
        (state == AttachmentState.offered ||
            state == AttachmentState.cancelled)) {
      final isRetry = state == AttachmentState.cancelled;
      final tooltip =
          isRetry ? l.attachmentRetryDownload : l.attachmentDownload;
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
/// full accessible label (file name interpolated); `IconButton.tooltip`
/// carries the short label. `busy` toggles `Semantics(enabled: !busy)` so
/// screen readers announce the disabled state.
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
        splashRadius: 20,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
