// The `.conversation-search` field and the `.conversation-filter` segmented
// toggle from chat-pane.css, shared by the desktop ConversationTools row and
// the mobile search panel.
//
// Both call sites previously built a `TextEditingController(text: search)`
// inside `build`, which recreates the controller on every rebuild and drops
// the caret back to offset 0. That was survivable while the screens only
// rebuilt on keystrokes; with the snapshot poll running every second it
// would fight the user mid-word. The box owns its controller and syncs it
// from the incoming value only when the two actually differ.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// React `.conversation-search` / `.conversation-filter { height: 34px }`.
const double kConversationToolHeight = 34;

/// React `.conversation-tools { margin: 12px 22px 0 }`.
const EdgeInsets kConversationToolsMargin = EdgeInsets.fromLTRB(22, 12, 22, 0);

/// React `.conversation-tools { gap: 10px }`.
const double kConversationToolsGap = 10;

/// The search field: a 34px pill at radius 8 on --bg-2 behind a --line
/// border, holding a --fg-3 glyph and a borderless 12.5px input. Focus
/// swaps the border to rgba(moss, 0.45) over --bg-0
/// (`.conversation-search:focus-within`).
class ConversationSearchBox extends StatefulWidget {
  const ConversationSearchBox({
    super.key,
    required this.search,
    required this.onSearch,
    required this.l,
    this.autofocus = false,
    this.focusNode,
  });

  final String search;
  final ValueChanged<String> onSearch;
  final AppLocalizations l;

  /// The mobile panel autofocuses on mount (React's `inputRef.current
  /// ?.focus()`); the desktop row does not.
  final bool autofocus;

  /// Supplied by the mobile panel so its test can assert focus.
  final FocusNode? focusNode;

  @override
  State<ConversationSearchBox> createState() => _ConversationSearchBoxState();
}

class _ConversationSearchBoxState extends State<ConversationSearchBox> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.search);
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant ConversationSearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The host owns the value. Only write it back when it genuinely
    // diverged (e.g. the mobile close button clearing the query), so a
    // rebuild triggered by anything else leaves the caret alone.
    if (widget.search != _controller.text) {
      _controller.text = widget.search;
    }
  }

  void _onFocusChange() {
    if (_focused == _focusNode.hasFocus) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    // Only dispose a node this widget created.
    if (widget.focusNode == null) _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.l.chatSearchPlaceholder,
      textField: true,
      child: Container(
        height: kConversationToolHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _focused ? MoshColors.bg0 : MoshColors.bg2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _focused
                ? MoshColors.moss.withValues(alpha: 0.45)
                : MoshColors.line,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.search,
              size: 16,
              color: _focused ? MoshColors.fg1 : MoshColors.fg3,
            ),
            const SizedBox(width: 8), // `.conversation-search { gap: 8px }`
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                onChanged: widget.onSearch,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 12.5, color: MoshColors.fg1),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: widget.l.chatSearchPlaceholder,
                  hintStyle:
                      const TextStyle(fontSize: 12.5, color: MoshColors.fg3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The `.conversation-filter` segment group: a 34px bordered --bg-2 track
/// with 3px of padding around two 26px radius-6 buttons at 11.5px/600. The
/// selected one sits on --bg-4 in --fg-1; the other is --fg-3.
class ConversationFilterToggle extends StatelessWidget {
  const ConversationFilterToggle({
    super.key,
    required this.attachmentsActive,
    required this.onAll,
    required this.onAttachments,
    required this.l,
  });

  final bool attachmentsActive;
  final VoidCallback onAll;
  final VoidCallback onAttachments;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: l.chatFilterAttachments,
      child: Container(
        height: kConversationToolHeight,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: MoshColors.bg2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MoshColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _FilterSegment(
              label: l.chatFilterAll,
              active: !attachmentsActive,
              onTap: onAll,
            ),
            _FilterSegment(
              label: l.chatFilterAttachments,
              icon: Icons.attach_file,
              active: attachmentsActive,
              onTap: onAttachments,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSegment extends StatelessWidget {
  const _FilterSegment({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    final color = active ? MoshColors.fg1 : MoshColors.fg3;
    return Material(
      color: active ? MoshColors.bg4 : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5), // `.conversation-filter { gap: 5px }`
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
