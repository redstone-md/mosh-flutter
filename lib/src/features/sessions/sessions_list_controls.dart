import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
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
    this.controller,
    required this.kind,
    required this.onSearch,
    required this.onKind,
  });

  final FocusNode focusNode;

  /// Owns the query, so it survives the field leaving the collapsed list.
  final TextEditingController? controller;
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
        // The chips line up with the search field; the clip reaches 2px
        // past it on each side so their outside focus ring still shows.
        ClipRect(
          clipper: const _FocusRingClip(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final entry in labels.entries) _filterChip(entry),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _search(BuildContext context, bool mobile, String hint) => TextField(
        key: const ValueKey('chat-list-search'),
        focusNode: focusNode,
        controller: controller,
        onChanged: onSearch,
        style: TextStyle(fontSize: 13, color: MoshColors.of(context).onSurface),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              fontSize: 13, color: MoshColors.of(context).onSurfaceMuted),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          enabledBorder: OutlineInputBorder(
              borderRadius: MoshShapes.control,
              borderSide:
                  BorderSide(color: MoshColors.of(context).outlineVariant)),
          prefixIconConstraints: const BoxConstraints(
              minWidth: kRailLeadingWidth + 8, minHeight: 40),
          prefixIcon: const Padding(
            padding: EdgeInsetsDirectional.only(end: 8),
            child: Icon(MoshIcons.search, size: 20),
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
                        style: TextStyle(
                            fontSize: 11,
                            color: MoshColors.of(context).onSurfaceMuted),
                      )),
                ),
        ),
      );

  Widget _filterChip(MapEntry<ConversationKind?, String> entry) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      // The Filter chip card: 32 px, inside a 48 px tap target on a phone.
      child: ChoiceChip(
        visualDensity: VisualDensity.standard,
        avatar: entry.key == null ? null : Icon(entry.key!.icon),
        label: Text(entry.value),
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
