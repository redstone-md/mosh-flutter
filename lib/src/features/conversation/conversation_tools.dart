// ConversationTools (message search + filter) for the DM screen, ported
// 1-1 from the React desktop surface in
// `src/features/private-dm/ConversationTools.tsx` (`ConversationTools`,
// `filterMessages`, `messageSearchText`, `SearchEmpty`). The mobile
// variants (`MobileConversationSearch`, `MobileConversationFilterNotice`)
// are deferred to a later atomic -- this file ports only the desktop
// in-scope surface.
//
// SHARED across all three conversation kinds (DM / channel / group).
// React has ONE generic `filterMessages<T extends SearchableMessage>` reused
// by `DmChatList`, `ChannelChatList`, and `GroupChatList` (MessageLists.tsx);
// this file mirrors that with a generic [filterMessages] + a small
// [SearchableMessage] interface the three message types satisfy. The
// channel / group feature folders add thin typed wrappers
// ([filterChannelMessages], [filterGroupMessages]) that delegate to the
// generic. This is option A (generalize) -- the faithful 1-1 of the React
// generic; the alternative (per-feature duplicated filters) would copy the
// ~15-line filter logic three times and violate DRY.
//
// Keeping the shared widgets + enum here (rather than a neutral
// `features/shared/`) is the same mild smell the prior `MultiPartySenderMeta`
// review accepted -- the channel / group features import this DM file,
// mirroring how they already import `conversation_helpers.dart`.
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
import 'package:mosh/src/features/conversation/conversation_search_box.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

// Re-export the mobile conversation search/filter widgets so the three
// screens (dm/channel/group) keep importing ONLY this file -- the same
// import that already pulls `ConversationTools` + `ConversationFilter` +
// `isMobileBreakpoint` also pulls the mobile trio, mirroring how React
// imports all of `ConversationTools`/`MobileConversation*` from one module.
export 'package:mosh/src/features/conversation/conversation_search_box.dart';
export 'package:mosh/src/features/conversation/mobile_conversation_search.dart';

/// Mirrors the React `ConversationFilter` type
/// (`"all" | "attachments"` in ConversationTools.tsx). `all` shows every
/// message; `attachments` keeps only messages that carry an attachment.
/// Shared across all three conversation kinds (DM / channel / group) -- the
/// React type is one definition reused by all three `*ChatList` components.
enum ConversationFilter { all, attachments }

/// Mobile vs desktop breakpoint shared across the three conversation
/// screens (DM / channel / group), 1-1 with React's `@media (max-width:
/// 580px)` rule (middle-column.css): width <= 580 is mobile (the desktop
/// `ConversationTools` row hides, the `MobileSearchToggle` header button +
/// `MobileConversationSearch` panel + `MobileConversationFilterNotice` strip
/// show); width > 580 is desktop. Uses [MediaQuery.sizeOf] (not
/// `MediaQuery.of`) so dependents only rebuild on width change, not on
/// every ancestor MediaQuery field (Flutter 3.10+ size-only selector).
bool isMobileBreakpoint(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= 580;

/// The searchable surface React's generic `filterMessages<T>` requires
/// (`SearchableMessage` in ConversationTools.tsx): a message exposes its
/// `fromDevice` name, its `body`, and an optional `AttachmentDescriptor`.
/// The three Flutter message types (`ChatMessage`, `ChannelMessage`,
/// `GroupMessage`) all satisfy this shape, but they share no generated
/// base class -- so this is a small abstract interface the screens adapt
/// their typed messages into. Keeping the interface here (rather than in
/// each feature) makes the generic filter one definition, matching
/// React's single `filterMessages<T>` (DRY -- option A, the faithful 1-1
/// of the React generic).
abstract interface class SearchableMessage {
  String get fromDevice;
  String get body;
  AttachmentDescriptor? get attachment;
}

/// Adapts any of the three message types into a [SearchableMessage] view.
/// Implemented as a tiny value class so the generic [filterMessages] can
/// call the getters without each message type implementing the interface
/// (the generated types are not under our control). The three concrete
/// types all expose `fromDevice`, `body`, and `attachment?` with identical
/// names, so one ctor serves all three.
class _SearchableView implements SearchableMessage {
  const _SearchableView(this.fromDevice, this.body, this.attachment);

  @override
  final String fromDevice;
  @override
  final String body;
  @override
  final AttachmentDescriptor? attachment;
}

/// Pure port of the React `filterMessages` (ConversationTools.tsx):
/// keep a message iff (filter != attachments OR attachment != null) AND
/// (the trimmed+lowercased query is empty OR the message's searchable
/// text includes the query). Order matters -- the React app filters
/// BEFORE grouping, and the Flutter screen does the same so the
/// grouping window stays correct on the visible set.
///
/// Returns a new list; the input is not mutated. Generic over [T] so the
/// channel / group / DM screens all share ONE implementation (1-1 with
/// React's single generic `filterMessages<T>`). Public so the three
/// feature screens and the unit tests can all reach it.
List<T> filterMessages<T>(
  List<T> messages,
  String search,
  ConversationFilter filter,
  SearchableMessage Function(T message) asSearchable,
) {
  final query = search.trim().toLowerCase();
  return messages.where((message) {
    final view = asSearchable(message);
    if (filter == ConversationFilter.attachments && view.attachment == null) {
      return false;
    }
    if (query.isEmpty) return true;
    return messageSearchText(view).contains(query);
  }).toList(growable: false);
}

/// Pure port of the React `messageSearchText`: join
/// `[from_device, body, attachment?.file_name, attachment?.mime]`,
/// drop null/empty pieces, lowercase. Kept public so the generic
/// [filterMessages] and the typed wrappers share one implementation. The
/// pieces are typed `String?` because the attachment fields are nullable;
/// the `.where` then drops nulls. This is the GENERIC search text -- it
/// does NOT include `fromFingerprint` for channel/group, matching React
/// (MessageLists.tsx channel/group `*ChatList` call the SAME `filterMessages`
/// with no fingerprint in the searchable text).
String messageSearchText(SearchableMessage message) {
  final pieces = <String?>[
    message.fromDevice,
    message.body,
    message.attachment?.fileName,
    message.attachment?.mime,
  ].where((s) => s != null && s.isNotEmpty);
  return pieces.join(' ').toLowerCase();
}

/// DM-typed wrapper over the generic [filterMessages]. Kept as a named
/// seam so the DM unit tests (`conversation_tools_test.dart`) drive the
/// same name they always have -- generalizing [filterMessages] to a
/// generic does not break them. Mirrors React's `DmChatList` passing its
/// `ChatMessage[]` to the generic `filterMessages`.
List<ChatMessage> filterDmMessages(
  List<ChatMessage> messages,
  String search,
  ConversationFilter filter,
) =>
    filterMessages(
      messages,
      search,
      filter,
      (m) => _SearchableView(m.fromDevice, m.body, m.attachment),
    );

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
    // React `.conversation-tools { margin: 12px 22px 0; gap: 10px }`.
    return Padding(
      padding: kConversationToolsMargin,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: ConversationSearchBox(
              search: search,
              onSearch: onSearch,
              l: l,
            ),
          ),
          const SizedBox(width: kConversationToolsGap),
          ConversationFilterToggle(
            attachmentsActive: filter == ConversationFilter.attachments,
            onAll: () => onFilter(ConversationFilter.all),
            onAttachments: () => onFilter(ConversationFilter.attachments),
            l: l,
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
