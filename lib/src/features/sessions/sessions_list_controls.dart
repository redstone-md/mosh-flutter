import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/conversation_kind_style.dart';
import 'package:mosh/src/features/sessions/rail_item.dart'
    show kRailLeadingWidth;
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
    final mobile = isMobileBreakpoint(context);
    final labels = <ConversationKind?, String>{
      null: l.chatFilterAll,
      ConversationKind.dm: l.chatListPersonal,
      ConversationKind.group: l.chatListGroups,
      ConversationKind.channel: l.chatListChannels,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _search(context, mobile, l.chatListSearch),
        // Native chip targets add 4px above the paint, or 8px on mobile.
        SizedBox(height: mobile ? 0 : 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              for (final entry in labels.entries) _filterChip(context, entry),
            ],
          ),
        ),
      ],
    );
  }

  Widget _search(BuildContext context, bool mobile, String hint) => TextField(
        key: const ValueKey('chat-list-search'),
        focusNode: focusNode,
        onChanged: onSearch,
        style: const TextStyle(fontSize: 13, color: MoshColors.fg1),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: MoshColors.fg3),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          enabledBorder: const OutlineInputBorder(
              borderRadius: MoshShapes.control,
              borderSide: BorderSide(color: MoshColors.lineStrong)),
          prefixIconConstraints: const BoxConstraints(
              minWidth: kRailLeadingWidth + 8, minHeight: 40),
          prefixIcon: const Padding(
            padding: EdgeInsetsDirectional.only(end: 8),
            child: Icon(Icons.search, size: 20),
          ),
          suffixIcon: mobile
              ? null
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Center(
                      widthFactor: 1,
                      child: Text(
                        Theme.of(context).platform == TargetPlatform.macOS
                            ? '⌘K'
                            : 'Ctrl+K',
                        style: const TextStyle(
                            fontSize: 11, color: MoshColors.fg3),
                      )),
                ),
        ),
      );

  Widget _filterChip(
      BuildContext context, MapEntry<ConversationKind?, String> entry) {
    final selected = entry.key == kind;
    final mobile = isMobileBreakpoint(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: ChoiceChip(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        labelPadding:
            EdgeInsets.symmetric(horizontal: 4, vertical: mobile ? 0 : 2),
        visualDensity: mobile ? VisualDensity.standard : VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        labelStyle: Theme.of(context).textTheme.labelMedium!.copyWith(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? MoshColors.fg1 : MoshColors.fg2,
            ),
        avatarBoxConstraints:
            const BoxConstraints.tightFor(width: 16, height: 16),
        avatar: entry.key == null
            ? null
            : Icon(entry.key!.icon,
                size: 16,
                color: Color.lerp(
                    MoshColors.fg2, entry.key!.accent, selected ? 1 : 0.55)),
        label: Text(entry.value),
        backgroundColor: MoshColors.bg0,
        selectedColor: entry.key?.tint ?? MoshColors.bg4,
        side: WidgetStateBorderSide.resolveWith((states) => BorderSide(
              width: 2,
              strokeAlign: BorderSide.strokeAlignOutside,
              color: states.contains(WidgetState.focused)
                  ? MoshColors.focusRing
                  : Colors.transparent,
            )),
        elevation: 0,
        pressElevation: 0,
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onKind(entry.key),
      ),
    );
  }
}
