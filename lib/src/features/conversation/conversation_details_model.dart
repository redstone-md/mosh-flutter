import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/features/conversation/peer_label.dart';
import 'package:mosh/src/util/format.dart';

typedef ConversationParticipant = ({String identity, String name});

class ConversationDetailsModel {
  ConversationDetailsModel(this.snapshot, this.l);

  final ConversationSnapshot snapshot;
  final AppLocalizations l;

  String get title => switch (snapshot) {
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
        (identity: source.fingerprint, name: source.displayName),
        if (source.peerDisplayName.isNotEmpty)
          (
            identity: source.peerMossId ?? source.sessionId,
            name: source.peerDisplayName
          ),
      ];
    }
    final authors = <String, String>{};
    for (final message in snapshot.messages) {
      final identity = message.fromFingerprint;
      if (identity != null) authors[identity] = message.fromDevice;
    }
    if (snapshot case GroupConversation(:final source)
        when source.memberPeerIds.isNotEmpty) {
      return [
        for (final id in source.memberPeerIds)
          (identity: id, name: authors[id] ?? shorten(id, 8))
      ];
    }
    return [
      for (final entry in authors.entries)
        (identity: entry.key, name: entry.value)
    ];
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
