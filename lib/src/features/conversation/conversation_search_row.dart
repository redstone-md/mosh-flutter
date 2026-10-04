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
    if (!isMobileBreakpoint(context) && chrome.mobileSearchOpen) {
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
