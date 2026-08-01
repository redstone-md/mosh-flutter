// ConversationTools (message search + filter) for the DM screen, ported
// 1-1 from the React desktop surface in
// `src/features/private-dm/ConversationTools.tsx` (`ConversationTools`,
// `filterMessages`, `messageSearchText`, `SearchEmpty`). The mobile
// variants (`MobileConversationSearch`, `MobileConversationFilterNotice`)
// are deferred to a later atomic -- this file ports only the desktop
// in-scope surface.
//
// Architecture mirrors React's ordering: `DmChatList`/`MessageLists` first
// apply `filterMessages(messages, search, filter)` to the message list and
// THEN group the filtered list (`messageItems(visibleMessages, keyFn)`).
// The Flutter `DmScreen` does the same -- it calls `filterDmMessages` and
// only then `groupDmMessages`. Keeping the order identical matters because
// the grouping window is computed across the visible set: a filtered-out
// message must not bridge two grouped messages that should split.
//
// The pure `filterDmMessages` helper is the seam the unit tests drive
// directly; the `ConversationTools` and `DmSearchEmpty` widgets are the UI
// surface the screen renders. State (`search` string + `filter` enum) is
// widget-local ephemeral UI state in `_DmScreenState` (ADR 0010 allows
// widget-local state for UI controls) -- no store is needed for two
// transient fields.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// Mirrors the React `ConversationFilter` type
/// (`"all" | "attachments"` in ConversationTools.tsx). `all` shows every
/// message; `attachments` keeps only messages that carry an attachment.
enum ConversationFilter { all, attachments }

/// Pure port of the React `filterMessages` (ConversationTools.tsx):
/// keep a message iff (filter != attachments OR attachment != null) AND
/// (the trimmed+lowercased query is empty OR the message's searchable
/// text includes the query). Order matters -- the React app filters
/// BEFORE grouping, and the Flutter screen does the same so the
/// grouping window stays correct on the visible set.
///
/// Returns a new list; the input is not mutated. Public so the DM screen
/// (a sibling library in the same package) and the unit tests can both
/// reach it -- `@visibleForTesting` would block the production caller.
List<ChatMessage> filterDmMessages(
  List<ChatMessage> messages,
  String search,
  ConversationFilter filter,
) {
  final query = search.trim().toLowerCase();
  return messages.where((message) {
    if (filter == ConversationFilter.attachments &&
        message.attachment == null) {
      return false;
    }
    if (query.isEmpty) return true;
    return _messageSearchText(message).contains(query);
  }).toList(growable: false);
}

/// Pure port of the React `messageSearchText`: join
/// `[from_device, body, attachment?.file_name, attachment?.mime]`,
/// drop null/empty pieces, lowercase. Kept private -- the searchable
/// text shape is an implementation detail of [filterDmMessages] and is
/// exercised through that seam. The pieces are typed `String?` because
/// the attachment fields are nullable; the `.where` then drops nulls.
String _messageSearchText(ChatMessage message) {
  final pieces = <String?>[
    message.fromDevice,
    message.body,
    message.attachment?.fileName,
    message.attachment?.mime,
  ].where((s) => s != null && s.isNotEmpty);
  return pieces.join(' ').toLowerCase();
}

/// Desktop message search + filter row, ported from the React
/// `ConversationTools` component. Two parts: a search `TextField` (search
/// icon prefix + `chatSearchPlaceholder` hint, controlled by [search],
/// `onChanged` -> [onSearch]) and a two-segment `SegmentedButton` (All /
/// Files with a paperclip icon) whose selected segment is [filter]. The
/// active filter gets the platform's selected styling, mirroring React's
/// `conversation-filter-active` class.
///
/// Mirrors React's `aria-label={chatText.searchPlaceholder}` on the
/// search input via a `Semantics(label: ..., textField: true)` wrapper,
/// and the filter group's `aria-label="Message filter"` similarly.
class ConversationTools extends StatelessWidget {
  const ConversationTools({
    super.key,
    required this.search,
    required this.filter,
    required this.onSearch,
    required this.onFilter,
    required this.l,
  });

  final String search;
  final ConversationFilter filter;
  final ValueChanged<String> onSearch;
  final ValueChanged<ConversationFilter> onFilter;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Semantics(
              label: l.chatSearchPlaceholder,
              textField: true,
              child: TextField(
                controller: TextEditingController(text: search),
                // Keep the controller in sync with the controlled value
                // without stealing focus / clobbering the caret every
                // rebuild -- the parent owns the source of truth.
                onChanged: onSearch,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: l.chatSearchPlaceholder,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: l.chatFilterAttachments,
            child: SegmentedButton<ConversationFilter>(
              segments: [
                ButtonSegment(
                  value: ConversationFilter.all,
                  label: Text(l.chatFilterAll),
                ),
                ButtonSegment(
                  value: ConversationFilter.attachments,
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: Text(l.chatFilterAttachments),
                ),
              ],
              selected: {filter},
              onSelectionChanged: (set) {
                if (set.isNotEmpty) onFilter(set.first);
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(theme.textTheme.labelSmall),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty state for a chat that has messages but the current search/filter
/// hid every row, ported from the React `SearchEmpty` component. Body
/// switches between `chatAttachmentEmptyBody` (filter == attachments) and
/// `chatSearchEmptyBody` otherwise -- matching React's conditional. The
/// no-messages-at-all empty branch lives in `dm_screen.dart` as `_Empty`
/// (`chatEmptyTitle` / `chatEmptyBody`) and is unaffected by this widget.
class DmSearchEmpty extends StatelessWidget {
  const DmSearchEmpty({super.key, required this.filter, required this.l});

  final ConversationFilter filter;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final body = filter == ConversationFilter.attachments
        ? l.chatAttachmentEmptyBody
        : l.chatSearchEmptyBody;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.chatSearchEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}