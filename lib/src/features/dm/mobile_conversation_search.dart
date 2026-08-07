// Mobile conversation search/filter UI, ported 1-1 from the React mobile
// variants in `src/features/private-dm/ConversationTools.tsx` L54-112
// (`MobileConversationSearch`, `MobileConversationFilterNotice`) and
// `src/features/private-dm/ActiveChatHeader.tsx` L103-131
// (`MobileSearchToggle` + `useMobileSearchPanel`).
//
// React renders three surfaces on narrow widths (the CSS `@media (max-width:
// 580px)` rule, mirrored by [isMobileBreakpoint]):
//   - `MobileSearchToggle` -- an icon button in the chat header `actions:`
//     that opens/closes the mobile search panel (tinted while open, mirroring
//     the `chat-mobile-only is-active` class).
//   - `MobileConversationSearch` -- a search `TextField` that AUTOFOCUSES on
//     mount + a close icon button that clears the query THEN closes (1-1 with
//     React L80-89: `tools.onSearch(""); onClose();`).
//   - `MobileConversationFilterNotice` -- a "Files + All reset" strip shown
//     only while the attachments filter is active (null when filter == all).
//
// This file ports ONLY the mobile surface; the desktop `ConversationTools`
// row + the `ConversationFilter` enum + `filterMessages` + the
// [isMobileBreakpoint] helper all live in `conversation_tools.dart`, which
// re-exports this file so the three screens keep a single import. The trio is
// pure presentation -- all search/filter state stays widget-local in the
// host screen (`_search` / `_filter` / `_mobileSearchOpen`), exactly as
// React keeps it in the `ConversationToolsState` + `useMobileSearchPanel`.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';

/// Header icon button that opens/closes the mobile search panel, 1-1 with
/// React `MobileSearchToggle` (ActiveChatHeader.tsx L113-131): a ghost icon
/// button carrying the `chat-mobile-only` class (rendered only on mobile by
/// the host gating it behind [isMobileBreakpoint]) with the `is-active` class
/// appended while open.
///
/// The icon is `Icons.search` at size 16 (React `IconSearch size=16`). The
/// tooltip/semantics flip between [AppLocalizations.chatSearchPlaceholder]
/// (closed) and [AppLocalizations.closeMessageSearch] (open), mirroring
/// React's `aria-label={open ? "Close message search" :
/// chatText.searchPlaceholder}`. The open state tints the icon with
/// `colorScheme.primary` to mirror the `is-active` class highlight.
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
        // Mirror React's `is-active` tint while the panel is open.
        color: open ? theme.colorScheme.primary : null,
      ),
      // React: `aria-label={open ? "Close message search" :
      // chatText.searchPlaceholder}`. Closed uses the search placeholder
      // (existing key); open uses the dedicated close label.
      tooltip: open ? l.closeMessageSearch : l.chatSearchPlaceholder,
      onPressed: onToggle,
    );
  }
}

/// Mobile search panel: an autofocusing search `TextField` + a close icon
/// button that clears the query THEN closes, 1-1 with React
/// `MobileConversationSearch` (ConversationTools.tsx L54-92).
///
/// Autofocus: React calls `inputRef.current?.focus()` in a mount `useEffect`.
/// The Flutter port uses an explicit [FocusNode] created in `initState` and
/// `requestFocus()`ed there, PLUS `autofocus: true` on the `TextField`. The
/// explicit node lets the widget tests assert focus after `pump`; the
/// `autofocus` flag is the belt-and-suspenders guarantee the framework
/// requests focus on the first frame regardless of the node's lifecycle.
///
/// The close button calls `onSearch("")` THEN `onClose()` -- order matters
/// (React L84-87), so the query clears before the panel unmounts, matching
/// the React `tools.onSearch(""); onClose();` sequence.
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
    // Autofocus on mount -- 1-1 with React's `useEffect(() =>
    // inputRef.current?.focus(), [])`. Requested in initState so the focus
    // lands on the first frame the widget is visible.
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
          // Close button -- 1-1 with React L79-90: clears the query THEN
          // closes (order matters; the panel unmounts after the clear).
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

/// Mobile "active filter" notice strip, 1-1 with React
/// `MobileConversationFilterNotice` (ConversationTools.tsx L95-114): renders
/// NOTHING while the filter is `all` (React returns `null`), and a small
/// row with a paperclip + the "Files" label + an "All" reset button while
/// the filter is `attachments`. Tapping "All" calls `onFilter(all)`.
///
/// The host renders this unconditionally (always in the layout) -- it
/// collapses to a zero-size [SizedBox.shrink] when the filter is `all`,
/// matching React's `null` return (a `SizedBox.shrink()` takes no space, the
/// same effective layout as React's `null` in a column).
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
    // 1-1 with React L100-102: `if (tools.filter !== "attachments") return
    // null;`. A zero-size box mirrors the layout effect of React's `null`.
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
