import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// The Invitation row card: who invites in [leading] and [title], to what
/// in [detail], and the two answers as buttons in the row, named by
/// [acceptLabel] and [declineLabel]. A null answer is a disabled button,
/// while a change to the invitation is on its way.
class InvitationRow extends StatelessWidget {
  const InvitationRow({
    super.key,
    required this.leading,
    required this.title,
    required this.detail,
    required this.acceptLabel,
    required this.declineLabel,
    required this.onAccept,
    required this.onDecline,
  });

  final Widget leading;
  final String title;
  final String detail;
  final String acceptLabel;
  final String declineLabel;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = MoshColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: MoshSpace.s12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: MoshSpace.s1, horizontal: MoshSpace.s3),
        child: Row(
          spacing: MoshSpace.s3,
          children: [
            ExcludeSemantics(child: leading),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _line(title, text.titleSmall!),
                  _line(detail,
                      text.bodySmall!.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: acceptLabel,
                onPressed: onAccept,
                // The answer that starts a chat is the accent of the row.
                color: colors.primary,
                icon: const Icon(MoshIcons.chat),
              ),
              IconButton(
                tooltip: declineLabel,
                onPressed: onDecline,
                icon: const Icon(MoshIcons.close),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _line(String value, TextStyle style) =>
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
}
