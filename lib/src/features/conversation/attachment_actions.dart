import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'conversation_attachment.dart';

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
    required this.attachment,
    required this.busy,
    required this.onDownload,
    required this.onCancel,
    required this.l,
  });

  final ConversationAttachment attachment;
  final bool busy;
  final void Function(String attachmentId) onDownload;
  final void Function(String attachmentId) onCancel;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final control = attachment.transferControl(busy: busy);
    if (control == null) return const SizedBox.shrink();
    final file = attachment.descriptor;
    final (icon, tooltip, label) = switch (control.action) {
      AttachmentTransferAction.download => (
          Icons.download,
          l.attachmentDownload,
          l.attachmentDownloadAria(file.fileName)
        ),
      AttachmentTransferAction.retryDownload => (
          Icons.download,
          l.attachmentRetryDownload,
          l.attachmentRetryDownloadAria(file.fileName)
        ),
      AttachmentTransferAction.retry => (
          Icons.refresh,
          l.attachmentRetry,
          l.attachmentRetryAria(file.fileName)
        ),
      AttachmentTransferAction.cancel => (
          Icons.close,
          l.attachmentCancelDownload,
          l.attachmentCancelDownloadAria(file.fileName)
        ),
    };
    return _ActionIcon(
      icon: icon,
      tooltip: tooltip,
      semanticsLabel: label,
      onPressed: control.enabled
          ? () => control.action == AttachmentTransferAction.cancel
              ? onCancel(file.attachmentId)
              : onDownload(file.attachmentId)
          : null,
      busy: !control.enabled,
    );
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
