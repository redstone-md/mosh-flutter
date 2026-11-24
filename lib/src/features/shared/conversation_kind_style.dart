import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

/// Type cues shared by the rail, its filters, and conversation headers.
extension ConversationKindStyle on ConversationKind {
  Color accent(MoshColors colors) => switch (this) {
        ConversationKind.dm => colors.primary,
        ConversationKind.group => colors.secondary,
        ConversationKind.channel => colors.tertiary,
      };

  Color tint(MoshColors colors) => accent(colors).withValues(alpha: 0.14);

  IconData get icon => switch (this) {
        ConversationKind.dm => MoshIcons.chat,
        ConversationKind.group => MoshIcons.group,
        ConversationKind.channel => MoshIcons.tag,
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
    this.plusIdentity,
  });

  final ConversationKind kind;
  final String name;
  final double radius;
  final bool online;
  final String? plusIdentity;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: kind.label(AppLocalizations.of(context)!),
        child: kind == ConversationKind.dm
            ? Stack(
                children: [
                  Avatar(
                      name: name, radius: radius, plusIdentity: plusIdentity),
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
                              color: MoshColors.of(context).success,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: MoshColors.of(context)
                                      .surfaceContainerLowest,
                                  width: 2),
                            ),
                          )),
                    ),
                ],
              )
            : CircleAvatar(
                radius: radius,
                backgroundColor: kind.tint(MoshColors.of(context)),
                foregroundColor: kind.accent(MoshColors.of(context)),
                child: Icon(kind.icon, size: radius),
              ),
      );
}
