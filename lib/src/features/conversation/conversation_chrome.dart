/// The parts of a conversation screen the user can drive: the search text,
/// the filter, the mobile search panel, the peer-status drawer, and leaving.
///
/// The screen owns these values. The header and the body both read them and
/// call back, so neither has to hold a copy.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show ConversationFilter;

@immutable
class ConversationChrome {
  const ConversationChrome({
    required this.search,
    required this.onSearch,
    required this.filter,
    required this.onFilter,
    required this.mobileSearchOpen,
    required this.onToggleMobileSearch,
    required this.onCloseMobileSearch,
    required this.showPeerStatus,
    required this.onOpenPeerStatus,
    required this.onClosePeerStatus,
    required this.onRequestLeave,
  });

  final String search;
  final ValueChanged<String> onSearch;

  final ConversationFilter filter;
  final ValueChanged<ConversationFilter> onFilter;

  /// Whether the narrow-window search panel is open. The header opens and
  /// closes it; the body only closes it.
  final bool mobileSearchOpen;
  final VoidCallback onToggleMobileSearch;
  final VoidCallback onCloseMobileSearch;

  /// Whether the peer-status drawer is open. The header opens it; the body
  /// draws it and closes it.
  final bool showPeerStatus;
  final VoidCallback onOpenPeerStatus;
  final VoidCallback onClosePeerStatus;

  /// Asks to leave the conversation. Shows the confirm dialog first.
  final Future<void> Function() onRequestLeave;
}

/// Builds a kind's app bar. Everything its buttons need is in [chrome].
typedef ConversationHeaderBuilder = PreferredSizeWidget Function(
  BuildContext context,
  ConversationChrome chrome,
);
