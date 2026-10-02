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

/// Personal initials with actual connection presence; groups/channels use type glyphs.
class ConversationKindAvatar extends StatelessWidget {
  const ConversationKindAvatar({
    super.key,
    required this.kind,
    required this.name,
    this.radius = 24,
    this.online = false,
  });

  final ConversationKind kind;
  final String name;
  final double radius;
  final bool online;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: kind.label(AppLocalizations.of(context)!),
        child: kind == ConversationKind.dm
            ? Stack(
                children: [
                  Avatar(name: name, radius: radius),
                  if (online)
                    PositionedDirectional(
                      bottom: 0,
                      end: 0,
                      child: Tooltip(
                          message: AppLocalizations.of(context)!.stateReady,
                          child: Container(
                            width: radius <= 20 ? 10 : 12,
                            height: radius <= 20 ? 10 : 12,
                            decoration: BoxDecoration(
                              color: kind.accent,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: MoshColors.bg0, width: 2),
                            ),
                          )),
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
