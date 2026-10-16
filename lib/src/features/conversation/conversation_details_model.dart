import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/features/conversation/peer_label.dart';
import 'package:mosh/src/util/format.dart';

typedef ConversationParticipant = ({
  String identity,
  String name,
  bool authenticated,
  bool own
});

class ConversationDetailsModel {
  ConversationDetailsModel(this.snapshot, this.l, {this.personalName});
  final String? personalName;

  final ConversationSnapshot snapshot;
  final AppLocalizations l;

  String get title => personalName ?? originalName;

  String get originalName => switch (snapshot) {
        DmConversation(:final source) => peerLabel(l, source),
        GroupConversation(:final source) =>
          source.label ?? l.summaryGroupFallbackTitle,
        ChannelConversation(:final source) => '#${source.name}',
      };

  String get subtitle => switch (snapshot) {
        DmConversation(:final source) => dmStateLabel(l, source.state),
        GroupConversation(:final source) =>
          l.membersCount(source.memberCount.toInt()),
        ChannelConversation() => l.channelNoticeTitle,
      };

  bool get knownAuthorsOnly => switch (snapshot) {
        ChannelConversation() => true,
        GroupConversation(:final source) => source.memberPeerIds.isEmpty,
        DmConversation() => false,
      };

  List<ConversationParticipant> get participants {
    if (snapshot case DmConversation(:final source)) {
      return [
        (
          identity: source.fingerprint,
          name: source.displayName,
          authenticated: true,
          own: true
        ),
        if (source.peerDisplayName.isNotEmpty)
          (
            identity: source.peerMossId ?? source.sessionId,
            name: source.peerDisplayName,
            authenticated: true,
            own: false
          ),
      ];
    }
    final authors = <String, ConversationParticipant>{};
    for (final message in snapshot.messages) {
      final identity = message.fromFingerprint;
      if (identity != null) {
        final authenticated = message.metadata?.origin != null;
        if (!authenticated && authors[identity]?.authenticated == true) {
          continue;
        }
        authors[identity] = (
          identity: identity,
          name: message.fromDevice,
          authenticated: authenticated,
          own: authenticated && message.metadata?.isOwn == true
        );
      }
    }
    if (snapshot case GroupConversation(:final source)
        when source.memberPeerIds.isNotEmpty) {
      return [
        for (final id in source.memberPeerIds)
          (authors[id] ??
              (
                identity: id,
                name: shorten(id, 8),
                authenticated: true,
                own: id == snapshot.ownFingerprint
              ))
      ];
    }
    return authors.values.toList();
  }

  List<ConversationMessage> get files {
    final byId = <String, ConversationMessage>{};
    for (final message in snapshot.messages) {
      final attachment = message.attachment;
      if (attachment != null) byId[attachment.attachmentId] = message;
    }
    return byId.values.toList().reversed.toList();
  }
}
