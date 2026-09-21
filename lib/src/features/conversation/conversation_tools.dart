// The message search box and the All/Files filter, plus the pure filter the
// message list runs before it groups rows.
//
// Shared by every conversation kind. The search text and the filter are
// widget state on the conversation screen: two values that live and die with
// the screen need no store.
//
// The mobile variants of the search box and the filter notice live in
// conversation_search_box.dart and mobile_conversation_search.dart, and are
// re-exported here so a screen needs one import.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_search_box.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';

export 'package:mosh/src/features/conversation/conversation_search_box.dart';
export 'package:mosh/src/features/conversation/mobile_conversation_search.dart';

/// What the filter keeps: every message, or only the ones with a file.
enum ConversationFilter { all, attachments }

/// Whether the window is narrow enough for the mobile chat layout. Below
/// this width the search row moves into the header and opens as a panel.
bool isMobileBreakpoint(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= 580;

/// Keeps the messages the search box and the filter leave visible: a
/// message survives when the filter is not "attachments" or it carries one,
/// and when the query is empty or appears in its searchable text.
///
/// Callers filter BEFORE grouping, so the 5-minute grouping window is worked
/// out across the rows the user actually sees. Returns a new list.
List<ConversationMessage> filterConversationMessages(
  List<ConversationMessage> messages,
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
    return messageSearchText(message).contains(query);
  }).toList(growable: false);
}

/// What the search box matches against: the sender name, the text, and the
/// attachment's file name and type. The fingerprint is deliberately left
/// out.
String messageSearchText(ConversationMessage message) {
  final pieces = <String?>[
    message.fromDevice,
    message.body,
    message.attachment?.fileName,
    message.attachment?.mime,
  ].where((piece) => piece != null && piece.isNotEmpty);
  return pieces.join(' ').toLowerCase();
}

/// The wide-window search row: a search box and an All/Files toggle.
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

/// Shown when a conversation has messages but the search or the filter hid
/// every one of them. The empty state for a conversation with no messages at
/// all is a different widget, built by the screen.
class ConversationSearchEmpty extends StatelessWidget {
  const ConversationSearchEmpty({
    super.key,
    required this.filter,
    required this.l,
  });

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
