import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';

/// One name/status rhythm for DMs, groups and public channels.
class ConversationHeaderTitle extends StatelessWidget {
  const ConversationHeaderTitle({
    super.key,
    required this.name,
    required this.subtitle,
    this.nameAction,
    this.onOpenDetails,
  });

  final String name;
  final String subtitle;
  final Widget? nameAction;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final titleStyle = chatTitleStyle(context);
    final subtitleStyle = chatSubtitleStyle(context);
    final titleHeight = scale.scale(titleStyle.fontSize!) * titleStyle.height!;
    final subtitleHeight =
        scale.scale(subtitleStyle.fontSize!) * subtitleStyle.height!;
    final gap = chatSubtitleGap(context);
    return SizedBox(
      height: math.max(titleHeight + gap + subtitleHeight, 41),
      width: double.infinity,
      child: Stack(children: [
        Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                  child: _name(context,
                      math.max(gap + subtitleHeight, 41 - titleHeight))),
              if (nameAction case final action?) action,
            ]),
        PositionedDirectional(
          start: 0,
          end: 0,
          top: titleHeight + gap,
          child: IgnorePointer(
              child: Text(subtitle,
                  style: subtitleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
        ),
      ]),
    );
  }

  Widget _name(BuildContext context, double bottomPadding) => Tooltip(
        message: AppLocalizations.of(context)!.chatDetailsTitle,
        child: InkWell(
          key: const ValueKey('conversation-header-details'),
          borderRadius: MoshShapes.control,
          onTap: onOpenDetails,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      );
}
