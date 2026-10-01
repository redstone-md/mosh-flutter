import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_shapes.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/press_scale.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';

/// A 40px leading icon with a light tint over the bubble's own surface.
///
/// Viewable MIME types keep an open affordance even when no thumbnail exists;
/// other files remain a decorative file/error icon. The outer semantics node
/// owns the full accessible label and excludes the IconButton's child
/// semantics, while its tooltip remains a visual hint.
const double kAttachmentThumbSize = 40;

/// Available files use the whole row as their keyboard and pointer target.
class AttachmentOpenTarget extends StatelessWidget {
  const AttachmentOpenTarget({
    super.key,
    required this.label,
    required this.onOpen,
    required this.child,
  });

  final String label;
  final VoidCallback? onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) => onOpen == null
      ? child
      : Tooltip(
          message: label,
          child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                  borderRadius: MoshShapes.embedded,
                  onTap: onOpen,
                  child: child)));
}

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
  final void Function(AttachmentDescriptor descriptor)? onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surface = MoshColors.fg1.withValues(alpha: 0.08);
    final icon = descriptor.mime.startsWith('image/')
        ? Icons.image_outlined
        : Icons.play_arrow;
    if (viewable && onOpen != null) {
      void onOpenPressed() => onOpen!(descriptor);
      return Semantics(
        label: l.attachmentOpenAria(descriptor.fileName),
        button: true,
        // IconButton also creates semantics for its tooltip. Replace that
        // subtree so only this full "Open <file>" action is announced.
        excludeSemantics: true,
        onTap: onOpenPressed,
        child: PressScale(
          child: Material(
            color: surface,
            borderRadius: MoshShapes.embedded,
            child: InkWell(
              borderRadius: MoshShapes.embedded,
              onTap: onOpenPressed,
              hoverColor: MoshColors.fg1.withValues(alpha: 0.14),
              child: SizedBox(
                width: kAttachmentThumbSize,
                height: kAttachmentThumbSize,
                child: Center(
                  child: Icon(
                    icon,
                    size: 20,
                    color: MoshColors.moss,
                  ),
                ),
              ),
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
        color: surface,
        borderRadius: MoshShapes.embedded,
      ),
      child: Icon(
        failed
            ? Icons.error_outline
            : viewable
                ? icon
                : Icons.insert_drive_file_outlined,
        size: 20,
        color: failed ? MoshColors.danger : MoshColors.fg2,
      ),
    );
  }
}
