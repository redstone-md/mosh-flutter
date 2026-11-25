import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show feedPadding, messageMeasure;
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';

/// The Typing hint card: who is writing, in one quiet line over the
/// composer and in line with its text.
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

  /// The localized `name is typing` shape; defaults to the ARB
  /// `typingHint` so tests can pin the wording without building the full
  /// localization delegate.
  final String Function(String name)? typingLabel;

  /// The line to show, or null when nobody is typing.
  String? _text(AppLocalizations? l) {
    if (names.isEmpty) return null;
    final label = typingLabel;
    if (label != null) {
      return names.length == 1
          ? label(names.first)
          : '${names.join(', ')} and others are typing';
    }
    if (l == null) return null;
    return names.length == 1
        ? l.typingHint(names.first)
        : '${names.join(', ')} ${l.typingHintAnd}';
  }

  @override
  Widget build(BuildContext context) {
    final text = _text(AppLocalizations.of(context));
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: text == null
          ? const SizedBox.shrink()
          : Padding(
              padding: EdgeInsets.symmetric(
                vertical: MoshSpace.s1,
                horizontal:
                    feedPadding(compact: isMobileBreakpoint(context)).left +
                        MoshSpace.s4,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  // No wider than a line of a message on the phone, as the
                  // card draws it on both devices.
                  constraints:
                      BoxConstraints(maxWidth: messageMeasure(compact: true)),
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium!
                        .copyWith(color: MoshColors.of(context).onSurfaceMuted),
                  ),
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
