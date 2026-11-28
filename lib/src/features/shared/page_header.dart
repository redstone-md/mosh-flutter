import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';

/// The Page header card: the head of a screen that is not a conversation.
/// Its name and, with [line], a line about the whole screen under it; with
/// [onBack] it is the phone's: the way back stands before a smaller name.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.line,
    this.onBack,
    this.backTooltip,
  });

  final String title;
  final String? line;
  final VoidCallback? onBack;
  final String? backTooltip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final phone = onBack != null;
    final name = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: phone ? text.titleLarge : text.headlineMedium),
        ),
        if (line case final about?) ...[
          if (!phone) const SizedBox(height: MoshSpace.s1),
          Text(about,
              style: (phone ? text.bodySmall : text.bodyMedium)!
                  .copyWith(color: MoshColors.of(context).onSurfaceVariant)),
        ],
      ],
    );
    if (!phone) return name;
    // The arrow, not the edge of its target, stands on the line the text
    // under the header starts on: the row is moved out by the target's
    // margin around the arrow, and stays pressable where it is drawn.
    return Transform.translate(
      offset: const Offset(-MoshSpace.s3, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: MoshSpace.s12),
        child: Row(children: [
          IconButton(
              tooltip: backTooltip,
              onPressed: onBack,
              icon: const Icon(MoshIcons.back)),
          const SizedBox(width: MoshSpace.s1),
          Expanded(child: name),
        ]),
      ),
    );
  }
}
