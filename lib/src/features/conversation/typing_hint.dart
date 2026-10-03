import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';

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
    final l = AppLocalizations.of(context);
    final String? text;
    if (names.isNotEmpty) {
      if (typingLabel != null) {
        text = names.length == 1
            ? typingLabel!(names.first)
            : '${names.join(', ')} and others are typing…';
      } else if (l != null) {
        text = names.length == 1
            ? l.typingHint(names.first)
            : '${names.join(', ')} ${l.typingHintAnd}';
      } else {
        text = null;
      }
    } else {
      text = null;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: text == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 11, color: MoshColors.fg3),
                ),
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
