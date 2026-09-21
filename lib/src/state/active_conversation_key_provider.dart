// The currently-active conversation key: the key [ConversationRef.key]
// renders, or null when no conversation is open.
//
// Kept in a Riverpod Notifier so the unread-lifecycle provider can read it
// and the chat screens can set/clear it on open/leave without threading a
// prop through every rebuild.
//
// Set by the sessions rail on select + the chat screens on open (initState);
// cleared on leave/close. null = no conversation open.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/conversation_target.dart';

/// Holds the active conversation key ([ConversationRef.key] renders the
/// format) or null when nothing is open.
final activeConversationKeyProvider =
    NotifierProvider<_ActiveConversationKeyNotifier, String?>(
  _ActiveConversationKeyNotifier.new,
);

/// Parsed active key: the conversation it names, plus the kind
/// discriminator and the snapshot-family argument (sessionId / channel name
/// / groupId -- the suffix after the ':' prefix) the existing callers read.
class ActiveConversation {
  const ActiveConversation(this.conversation);

  /// The open conversation, as the value the state layer names
  /// conversations with. A caller that re-reads it hands this straight to
  /// `invalidateConversation` instead of branching on the kind itself.
  final ConversationRef conversation;

  /// The snapshot-family argument: the conversation's id.
  String get arg => conversation.id;

  /// Which kind the open conversation is. [ConversationKind] is the one
  /// kind enum, so no second spelling is minted here.
  ConversationKind get kind => conversation.kind;

  /// Reads a key back, or returns null when it names no conversation.
  ///
  /// [ConversationRef.tryParse] owns the grammar; this keeps only the
  /// projection the existing callers read. A key with an empty id parses to
  /// "nothing open" rather than to a conversation with a blank id.
  static ActiveConversation? parse(String? key) {
    final ref = ConversationRef.tryParse(key);
    if (ref == null) return null;
    return ActiveConversation(ref);
  }
}

/// The parsed [ActiveConversation] for the current key, or null when no
/// conversation is open. The single parse site for the titlebar, the shell
/// drawer, and the auto-poll loop.
final activeConversationProvider = Provider<ActiveConversation?>(
  (ref) => ActiveConversation.parse(ref.watch(activeConversationKeyProvider)),
);

class _ActiveConversationKeyNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Sets the active conversation key (called on open/select).
  void set(String? key) {
    if (state == key) return;
    state = key;
  }

  /// Clears the active key to null (called on leave/close).
  void clear() {
    if (state == null) return;
    state = null;
  }
}
