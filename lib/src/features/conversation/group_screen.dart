/// A private or org group. Everything but the header comes from the shared
/// conversation screen.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/features/conversation/conversation_screen.dart';
import 'package:mosh/src/features/conversation/group_screen_header.dart';
import 'package:mosh/src/gateway/conversation_target.dart' show GroupTarget;

class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.groupId});

  /// The group id. Groups are keyed by id, not by their label, which can be
  /// empty and is not unique.
  final String groupId;

  @override
  Widget build(BuildContext context) => ConversationScreen(
        target: GroupTarget(groupId),
        header: (context, chrome) => GroupScreenHeader(
          groupId: groupId,
          onOpenPeerStatus: chrome.onOpenPeerStatus,
          onLeave: chrome.onRequestLeave,
          mobileSearchOpen: chrome.mobileSearchOpen,
          onToggleMobileSearch: chrome.onToggleMobileSearch,
          filter: chrome.filter,
          onFilter: chrome.onFilter,
        ),
      );
}
