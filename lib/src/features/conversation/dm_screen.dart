/// A private DM. Everything but the header comes from the shared
/// conversation screen.
///
/// The DM keeps one piece of state of its own: whether the user has
/// confirmed this session's safety number in person. It is client-side only
/// and lasts as long as the screen does. The header takes a set because it
/// was written against several sessions at once; only this one is ever in
/// it.
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
  Set<String> _confirmedSessionIds = {};

  @override
  Widget build(BuildContext context) => ConversationScreen(
        target: DmTarget(widget.sessionId),
        onLeft: _forgetConfirmation,
        header: (context, chrome) => DmScreenHeader(
          sessionId: widget.sessionId,
          onOpenPeerStatus: chrome.onOpenPeerStatus,
          onLeave: chrome.onRequestLeave,
          mobileSearchOpen: chrome.mobileSearchOpen,
          onToggleMobileSearch: chrome.onToggleMobileSearch,
          filter: chrome.filter,
          onFilter: chrome.onFilter,
          onStartCall: _startCall,
          confirmedFingerprints: _confirmedSessionIds,
          onConfirmFingerprint: _confirmFingerprint,
        ),
      );

  Future<void> _startCall() async {
    final call = ref.read(conversationCallBindingProvider);
    if (call == null) return;
    final error = await call.start(ref, widget.sessionId);
    if (!mounted || error == null) return;
    showActionErrorSnackBar(context, error);
  }

  void _confirmFingerprint() => setState(
        () => _confirmedSessionIds = {
          ..._confirmedSessionIds,
          widget.sessionId,
        },
      );

  /// The session is gone, so its confirmation no longer means anything.
  void _forgetConfirmation() {
    if (!mounted) return;
    setState(() => _confirmedSessionIds = {..._confirmedSessionIds}
      ..remove(widget.sessionId));
  }
}
