import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

/// Type cues shared by the rail, its filters, and conversation headers.
extension ConversationKindStyle on ConversationKind {
  Color get accent => switch (this) {
        ConversationKind.dm => MoshColors.dmAccent,
        ConversationKind.group => MoshColors.groupAccent,
        ConversationKind.channel => MoshColors.channelAccent,
      };

  Color get tint => accent.withValues(alpha: 0.14);

  IconData get icon => switch (this) {
        ConversationKind.dm => Icons.chat_bubble_outline,
        ConversationKind.group => Icons.group_outlined,
        ConversationKind.channel => Icons.tag,
      };

  String label(AppLocalizations l) => switch (this) {
        ConversationKind.dm => l.conversationTypeDm,
        ConversationKind.group => l.conversationTypeGroup,
        ConversationKind.channel => l.conversationTypeChannel,
      };
}

/// Keeps personal initials while giving each conversation type a stable cue.
class ConversationKindAvatar extends StatelessWidget {
  const ConversationKindAvatar({
    super.key,
    required this.kind,
    required this.name,
    this.radius = 24,
  });

  final ConversationKind kind;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: kind.label(AppLocalizations.of(context)!),
        child: kind == ConversationKind.dm
            ? Stack(
                children: [
                  Avatar(name: name, radius: radius),
                  PositionedDirectional(
                    bottom: 0,
                    end: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: kind.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: MoshColors.bg0, width: 2),
                      ),
                      child:
                          Icon(kind.icon, size: 10, color: MoshColors.mossInk),
                    ),
                  ),
                ],
              )
            : CircleAvatar(
                radius: radius,
                backgroundColor: kind.tint,
                foregroundColor: kind.accent,
                child: Icon(kind.icon, size: radius),
              ),
      );
}
