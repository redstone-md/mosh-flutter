/// What the confirm dialog says before the user leaves a conversation.
///
/// The wording is the one thing about leaving that follows the kind: a DM is
/// deleted, a channel and a group are left, and each names itself
/// differently.
library;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/util/format.dart' show shorten;

/// How many characters of an id to show when there is no better name.
const int _shortIdLength = 6;

class ConversationLeavePrompt {
  const ConversationLeavePrompt({
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  /// Builds the prompt for [target]. [snapshot] is null while the
  /// conversation is still loading, which is why every name has a fallback.
  factory ConversationLeavePrompt.of(
    AppLocalizations l,
    AnyConversationTarget target,
    ConversationSnapshot? snapshot,
  ) =>
      switch (target.kind) {
        ConversationKind.dm => ConversationLeavePrompt(
            title: l.deleteChatTitle(_peerName(target, snapshot)),
            body: l.deleteChatBody,
            confirmLabel: l.deleteChatConfirm,
          ),
        ConversationKind.channel => ConversationLeavePrompt(
            title: l.leaveChannelTitle(target.id),
            body: l.leaveChannelBody,
            confirmLabel: l.leaveChannelConfirm,
          ),
        ConversationKind.group => ConversationLeavePrompt(
            title: l.leaveGroupTitle(_groupName(target, snapshot)),
            body: l.leaveGroupBody,
            confirmLabel: l.leaveGroupConfirm,
          ),
      };

  final String title;
  final String body;
  final String confirmLabel;
}

/// The peer's name, falling back to the session id until their first message
/// tells us what they are called.
String _peerName(
  AnyConversationTarget target,
  ConversationSnapshot? snapshot,
) {
  if (snapshot is! DmConversation) return target.id;
  final name = snapshot.source.peerDisplayName;
  return name.isEmpty ? snapshot.source.sessionId : name;
}

/// The group's label, falling back to a short form of its id. A group does
/// not have to be named.
String _groupName(
  AnyConversationTarget target,
  ConversationSnapshot? snapshot,
) {
  final label = snapshot is GroupConversation ? snapshot.source.label : null;
  return label ?? shorten(target.id, _shortIdLength);
}
