// Mobile conversation search/filter UI.
//
// Three surfaces on narrow widths (below [isMobileBreakpoint]):
//   - `MobileSearchToggle` -- an icon button in the chat header `actions:`
//     that opens/closes the mobile search panel (tinted while open).
//   - `MobileConversationSearch` -- a search `TextField` that AUTOFOCUSES on
//     mount + a close icon button that clears the query THEN closes.
//   - `MobileConversationFilterNotice` -- a "Files + All reset" strip shown
//     only while the attachments filter is active (nothing when filter ==
//     all).
//
// This file holds ONLY the mobile surface; the desktop `ConversationTools`
// row + the `ConversationFilter` enum + `filterMessages` + the
// [isMobileBreakpoint] helper all live in `conversation_tools.dart`, which
// re-exports this file so the three screens keep a single import. The trio is
// pure presentation -- all search/filter state stays widget-local in the
// host screen (`_search` / `_filter` / `_mobileSearchOpen`).
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';

/// Header icon button that opens/closes the mobile search panel: a ghost
/// icon button (rendered only on mobile by the host gating it behind
/// [isMobileBreakpoint]).
///
/// The icon is `Icons.search` at size 16. The tooltip/semantics flip
/// between [AppLocalizations.chatSearchPlaceholder] (closed) and
/// [AppLocalizations.closeMessageSearch] (open). The open state tints the
/// icon with `colorScheme.primary` as the active highlight.
class MobileSearchToggle extends StatelessWidget {
  const MobileSearchToggle({
    super.key,
    required this.open,
    required this.onToggle,
    required this.l,
  });

  final bool open;
  final VoidCallback onToggle;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      icon: Icon(
        Icons.search,
        size: 16,
        // Tint while the panel is open.
        color: open ? theme.colorScheme.primary : null,
      ),
      // Closed uses the search placeholder (existing key); open uses the
      // dedicated close label.
      tooltip: open ? l.closeMessageSearch : l.chatSearchPlaceholder,
      onPressed: onToggle,
    );
  }
}

/// Mobile search panel: an autofocusing search `TextField` + a close icon
/// button that clears the query THEN closes.
///
/// Autofocus uses an explicit [FocusNode] created in `initState` and
/// `requestFocus()`ed there, PLUS `autofocus: true` on the `TextField`. The
/// explicit node lets the widget tests assert focus after `pump`; the
/// `autofocus` flag is the belt-and-suspenders guarantee the framework
/// requests focus on the first frame regardless of the node's lifecycle.
///
/// The close button calls `onSearch("")` THEN `onClose()` -- order matters,
/// so the query clears before the panel unmounts.
class MobileConversationSearch extends StatefulWidget {
  const MobileConversationSearch({
    super.key,
    required this.search,
    required this.onSearch,
    required this.onClose,
    required this.l,
  });

  final String search;
  final ValueChanged<String> onSearch;
  final VoidCallback onClose;
  final AppLocalizations l;

  @override
  State<MobileConversationSearch> createState() =>
      _MobileConversationSearchState();
}

class _MobileConversationSearchState extends State<MobileConversationSearch> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Autofocus on mount. Requested in initState so the focus lands on
    // the first frame the widget is visible.
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: kConversationToolsMargin,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: ConversationSearchBox(
              search: widget.search,
              onSearch: widget.onSearch,
              l: widget.l,
              autofocus: true,
              focusNode: _focusNode,
            ),
          ),
          const SizedBox(width: kConversationToolsGap),
          // Close button: clears the query THEN closes (order matters; the
          // panel unmounts after the clear).
          IconButton(
            icon: const Icon(Icons.close, size: 15),
            tooltip: widget.l.closeMessageSearch,
            onPressed: () {
              widget.onSearch('');
              widget.onClose();
            },
          ),
        ],
      ),
    );
  }
}

/// Mobile "active filter" notice strip: renders NOTHING while the filter
/// is `all`, and a small row with a paperclip + the "Files" label + an
/// "All" reset button while the filter is `attachments`. Tapping "All"
/// calls `onFilter(all)`.
///
/// The host renders this unconditionally (always in the layout) -- it
/// collapses to a zero-size [SizedBox.shrink] when the filter is `all`
/// (takes no space, so the effective layout is "not rendered").
class MobileConversationFilterNotice extends StatelessWidget {
  const MobileConversationFilterNotice({
    super.key,
    required this.filter,
    required this.onFilter,
    required this.l,
  });

  final ConversationFilter filter;
  final ValueChanged<ConversationFilter> onFilter;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    // Nothing to notice when the files filter is off.
    if (filter != ConversationFilter.attachments) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          Icon(Icons.attach_file, size: 13, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(l.chatFilterAttachments)),
          TextButton(
            onPressed: () => onFilter(ConversationFilter.all),
            child: Text(l.chatFilterAll),
          ),
        ],
      ),
    );
  }
}
