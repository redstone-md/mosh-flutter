/// The [[Typing indicator]] hint: "the counterpart is typing" for a DM,
/// "Alice is typing…" per member for a group. Renders nothing when nobody
/// is typing, so callers mount it unconditionally under the message list.
///
/// The state comes from the snapshot the poll already cycles — the DM's
/// `peerTypingUntilMs` and the group's `typingMembers`, each checked
/// against the clock here so an expired hint disappears on the next
/// rebuild without a timer. Channels never carry typing, so a channel
/// snapshot renders nothing (no field to read).
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';

/// React has no equivalent rail line; this hint rides above the composer
/// in the message pane, sized to the `.message-time` row tokens (11px
/// fg-3) so it reads as meta, not a message.
class TypingHint extends StatelessWidget {
  const TypingHint({
    super.key,
    required this.names,
    this.typingLabel,
  });

  /// The display names of everyone typing right now. Empty renders
  /// nothing. One name renders the DM shape and a group's single typer
  /// the same way; several names join with the localized "and".
  final List<String> names;

  /// The localized `name is typing…` shape; defaults to the ARB
  /// `typingHint` so tests can pin the wording without building the full
  /// localization delegate.
  final String Function(String name)? typingLabel;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    final label = typingLabel ?? l.typingHint;
    final text = names.length == 1
        ? label(names.first)
        // A multi-typer group joins the names the same way the rail joins
        // subtitles; the localized "and" keeps the word order per locale.
        : '${names.join(', ')} ${l.typingHintAnd}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, color: MoshColors.fg3),
        ),
      ),
    );
  }
}

/// Who is typing in this conversation, from the sealed snapshot view:
/// the DM's counterpart name (peer display name, fallback "the peer"),
/// or the group's per-member display names. A channel has no typing, so
/// its answer is always empty.
List<String> typingNames(ConversationSnapshot snapshot) {
  switch (snapshot) {
    case DmConversation(:final peerTyping, :final source):
      if (!peerTyping) return const [];
      final peer = source.peerDisplayName.trim();
      return [peer.isEmpty ? source.state.name : peer];
    case GroupConversation(:final membersTyping):
      return membersTyping.map((member) => member.displayName).toList();
    case ChannelConversation():
      return const [];
  }
}
