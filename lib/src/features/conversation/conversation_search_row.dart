/// The row above the message list that narrows what it shows.
///
/// A wide window puts the search box and the All/Files toggle side by side.
/// A narrow one moves the search into a panel the header opens, and leaves a
/// strip saying the filter is on.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_chrome.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';

class ConversationSearchRow extends StatelessWidget {
  const ConversationSearchRow({super.key, required this.chrome});

  final ConversationChrome chrome;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (!isMobileBreakpoint(context)) {
      return ConversationTools(
        search: chrome.search,
        filter: chrome.filter,
        onSearch: chrome.onSearch,
        onFilter: chrome.onFilter,
        l: l,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (chrome.mobileSearchOpen)
          MobileConversationSearch(
            search: chrome.search,
            onSearch: chrome.onSearch,
            onClose: chrome.onCloseMobileSearch,
            l: l,
          ),
        MobileConversationFilterNotice(
          filter: chrome.filter,
          onFilter: chrome.onFilter,
          l: l,
        ),
      ],
    );
  }
}
