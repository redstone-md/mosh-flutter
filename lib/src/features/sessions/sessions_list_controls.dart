import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/conversation_kind_style.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;

/// Shared only so the shell shortcut can focus the mounted rail search.
final chatListSearchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'chat-list-search');
  ref.onDispose(node.dispose);
  return node;
});

class SessionsListControls extends StatelessWidget {
  const SessionsListControls({
    super.key,
    required this.focusNode,
    required this.kind,
    required this.onSearch,
    required this.onKind,
  });

  final FocusNode focusNode;
  final ConversationKind? kind;
  final ValueChanged<String> onSearch;
  final ValueChanged<ConversationKind?> onKind;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final labels = <ConversationKind?, String>{
      null: l.chatFilterAll,
      ConversationKind.dm: l.chatListPersonal,
      ConversationKind.group: l.chatListGroups,
      ConversationKind.channel: l.chatListChannels,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('chat-list-search'),
          focusNode: focusNode,
          onChanged: onSearch,
          decoration: InputDecoration(
            hintText: l.chatListSearch,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: isMobileBreakpoint(context)
                ? null
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Center(
                        widthFactor: 1,
                        child: Text(
                          Theme.of(context).platform == TargetPlatform.macOS
                              ? '⌘K'
                              : 'Ctrl+K',
                          style: Theme.of(context).textTheme.bodySmall,
                        )),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in labels.entries) _filterChip(context, entry),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(
          BuildContext context, MapEntry<ConversationKind?, String> entry) =>
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: ChoiceChip(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelStyle: Theme.of(context).textTheme.labelMedium,
          avatarBoxConstraints:
              const BoxConstraints.tightFor(width: 16, height: 16),
          avatar: entry.key == null
              ? null
              : Icon(entry.key!.icon, size: 16, color: entry.key!.accent),
          label: Text(entry.value),
          selectedColor: entry.key?.tint,
          selected: entry.key == kind,
          showCheckmark: false,
          onSelected: (_) => onKind(entry.key),
        ),
      );
}
