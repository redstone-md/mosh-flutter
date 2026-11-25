import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/shared/search_field.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

/// Shared only so the shell shortcut can focus the mounted rail search.
final chatListSearchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'chat-list-search');
  ref.onDispose(node.dispose);
  return node;
});

/// The search of the chat list over the filters by kind of conversation.
class SessionsListControls extends StatelessWidget {
  const SessionsListControls({
    super.key,
    required this.focusNode,
    required this.controller,
    required this.kind,
    required this.onSearch,
    required this.onKind,
  });

  final FocusNode focusNode;

  /// Owns the query, so it survives the field leaving the collapsed list.
  final TextEditingController controller;
  final ConversationKind? kind;
  final ValueChanged<String> onSearch;
  final ValueChanged<ConversationKind?> onKind;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // The card's gap around the filters; a phone's chip adds its 48 px tap
    // target to it.
    const gap = MoshSpace.s2;
    final labels = <ConversationKind?, String>{
      null: l.chatFilterAll,
      ConversationKind.dm: l.chatListPersonal,
      ConversationKind.group: l.chatListGroups,
      ConversationKind.channel: l.chatListChannels,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _search(context, l.chatListSearch),
        const SizedBox(height: gap),
        // The chips line up with the search field; the clip reaches 2px
        // past it on each side so their outside focus ring still shows.
        ClipRect(
          clipper: const _FocusRingClip(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final entry in labels.entries) _filterChip(context, entry),
              ],
            ),
          ),
        ),
        const SizedBox(height: gap),
      ],
    );
  }

  /// The search field; a device with a keyboard sees the keys that focus it.
  Widget _search(BuildContext context, String hint) {
    final platform = Theme.of(context).platform;
    return SearchField(
      key: const ValueKey('chat-list-search'),
      focusNode: focusNode,
      controller: controller,
      hint: hint,
      onChanged: onSearch,
      shortcut: MoshControl.touch(platform)
          ? null
          : platform == TargetPlatform.macOS
              ? '⌘K'
              : 'Ctrl K',
    );
  }

  Widget _filterChip(
      BuildContext context, MapEntry<ConversationKind?, String> entry) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      // The Filter chip card: 32 px, inside a 48 px tap target on a phone.
      child: ChoiceChip(
        visualDensity: VisualDensity.standard,
        label: Text(entry.value, overflow: TextOverflow.ellipsis),
        selected: entry.key == kind,
        onSelected: (_) => onKind(entry.key),
      ),
    );
  }
}

/// The scroller's bounds widened by a chip's 2px outside focus ring.
class _FocusRingClip extends CustomClipper<Rect> {
  const _FocusRingClip();

  @override
  Rect getClip(Size size) => (Offset.zero & size).inflate(2);

  @override
  bool shouldReclip(_FocusRingClip oldClipper) => false;
}
