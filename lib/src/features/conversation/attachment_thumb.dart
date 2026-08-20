import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/rust/conversation/attachments.dart';

/// The file-card leading surface: React `.attachment-thumb { width: 40px;
/// height: 40px; border-radius: 8px; background: var(--bg-3); color:
/// var(--fg-3) }`.
///
/// Viewable MIME types keep an open affordance even when no thumbnail exists;
/// other files remain a decorative file/error icon. The play glyph is the
/// shared React `IconPlayerPlayFilled` affordance for all viewable types.
/// The outer semantics node owns the full accessible label and excludes the
/// IconButton's child semantics, while its tooltip remains a visual hint.
/// React `.attachment-thumb { width: 40px; height: 40px }`.
const double kAttachmentThumbSize = 40;

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
        child: Material(
          color: MoshColors.bg3,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onOpenPressed,
            // `.attachment-thumb-button { color: var(--moss) }` with a
            // --bg-4 hover.
            hoverColor: MoshColors.bg4,
            child: const SizedBox(
              width: kAttachmentThumbSize,
              height: kAttachmentThumbSize,
              child: Icon(Icons.play_arrow, size: 20, color: MoshColors.moss),
            ),
          ),
        ),
      );
    }

    return Container(
      width: kAttachmentThumbSize,
      height: kAttachmentThumbSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MoshColors.bg3,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        failed ? Icons.error_outline : Icons.insert_drive_file_outlined,
        size: 20,
        color: failed ? MoshColors.danger : MoshColors.fg3,
      ),
    );
  }
}
