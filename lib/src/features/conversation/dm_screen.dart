/// A private DM. Everything but the header comes from the shared
/// conversation screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/features/conversation/conversation_call_binding.dart'
    show conversationCallBindingProvider;
import 'package:mosh/src/features/conversation/conversation_screen.dart';
import 'package:mosh/src/features/conversation/dm_screen_header.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/gateway/conversation_target.dart' show DmTarget;

class DmScreen extends ConsumerStatefulWidget {
  const DmScreen({super.key, required this.sessionId});

  /// The DM session id.
  final String sessionId;

  @override
  ConsumerState<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends ConsumerState<DmScreen> {
  @override
  Widget build(BuildContext context) => ConversationScreen(
        target: DmTarget(widget.sessionId),
        header: (context, chrome) => DmScreenHeader(
          sessionId: widget.sessionId,
          onOpenPeerStatus: chrome.onOpenPeerStatus,
          onLeave: chrome.onRequestLeave,
          mobileSearchOpen: chrome.mobileSearchOpen,
          onToggleMobileSearch: chrome.onToggleMobileSearch,
          filter: chrome.filter,
          onFilter: chrome.onFilter,
          onStartCall: _startCall,
        ),
      );

  Future<void> _startCall() async {
    final call = ref.read(conversationCallBindingProvider);
    if (call == null) return;
    final error = await call.start(ref, widget.sessionId);
    if (!mounted || error == null) return;
    showActionErrorSnackBar(context, error);
  }
}
