import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// The file-card leading surface, matching React's `attachment-thumb`.
/// Viewable MIME types keep an open affordance even when no thumbnail exists;
/// other files remain a decorative file/error icon. The play glyph is the
/// shared React `IconPlayerPlayFilled` affordance for all viewable types.
/// The outer semantics node owns the full accessible label and excludes the
/// IconButton's child semantics, while its tooltip remains a visual hint.
class AttachmentThumb extends StatelessWidget {
  const AttachmentThumb({
    super.key,
    required this.descriptor,
    required this.viewable,
    required this.failed,
    required this.onOpen,
  });

  final AttachmentDescriptor descriptor;
  final bool viewable;
  final bool failed;
  final void Function(AttachmentDescriptor descriptor) onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (viewable) {
      void onOpenPressed() => onOpen(descriptor);
      return Semantics(
        label: l.attachmentOpenAria(descriptor.fileName),
        button: true,
        // IconButton also creates semantics for its tooltip. Replace that
        // subtree so only this full "Open <file>" action is announced.
        excludeSemantics: true,
        onTap: onOpenPressed,
        child: IconButton(
          icon: const Icon(Icons.play_arrow, size: 20),
          tooltip: l.attachmentOpen,
          onPressed: onOpenPressed,
          visualDensity: VisualDensity.compact,
          splashRadius: 18,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
        ),
      );
    }

    return Icon(
      failed ? Icons.error_outline : Icons.insert_drive_file_outlined,
      size: 22,
      color: failed ? Theme.of(context).colorScheme.error : null,
    );
  }
}
