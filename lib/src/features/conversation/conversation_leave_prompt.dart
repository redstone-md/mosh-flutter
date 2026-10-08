import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

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
            title: switch (_peerName(snapshot)) {
              final name? => l.deleteChatTitle(name),
              _ => l.deleteChatUnnamedTitle,
            },
            body: l.deleteChatBody,
            confirmLabel: l.deleteChatConfirm,
          ),
        ConversationKind.channel => ConversationLeavePrompt(
            title: l.leaveChannelTitle(target.id),
            body: l.leaveChannelBody,
            confirmLabel: l.leaveChannelConfirm,
          ),
        ConversationKind.group => ConversationLeavePrompt(
            title: switch (_groupName(snapshot)) {
              final name? => l.leaveGroupTitle(name),
              _ => l.leaveGroupUnnamedTitle,
            },
            body: l.leaveGroupBody,
            confirmLabel: l.leaveGroupConfirm,
          ),
      };

  final String title;
  final String body;
  final String confirmLabel;
}

/// Technical session IDs belong in details, never in confirmation titles.
String? _peerName(ConversationSnapshot? snapshot) {
  if (snapshot is! DmConversation) return null;
  final name = snapshot.source.peerDisplayName;
  return name.isEmpty || name == snapshot.source.sessionId ? null : name;
}

String? _groupName(ConversationSnapshot? snapshot) {
  final label = snapshot is GroupConversation ? snapshot.source.label : null;
  return label == null || label.trim().isEmpty ? null : label;
}
