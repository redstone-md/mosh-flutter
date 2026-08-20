/// A private DM. Everything but the header comes from the shared
/// conversation screen.
///
/// The DM keeps one piece of state of its own: which peer fingerprints the
/// user has confirmed in person. It is client-side only and lasts as long as
/// the screen does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/features/conversation/conversation_screen.dart';
import 'package:mosh/src/features/dm/dm_screen_header.dart';
import 'package:mosh/src/features/dm/voice_call_layer.dart' show startVoiceCall;
import 'package:mosh/src/gateway/conversation_target.dart' show DmTarget;
import 'package:mosh/src/util/format.dart' show readableError;

class DmScreen extends ConsumerStatefulWidget {
  const DmScreen({super.key, required this.sessionId});

  /// The DM session id.
  final String sessionId;

  @override
  ConsumerState<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends ConsumerState<DmScreen> {
  Set<String> _confirmedFingerprints = {};

  @override
  Widget build(BuildContext context) => ConversationScreen(
        target: DmTarget(widget.sessionId),
        onLeft: _forgetConfirmation,
        header: (context, hooks) => DmScreenHeader(
          sessionId: widget.sessionId,
          onOpenPeerStatus: hooks.onOpenPeerStatus,
          onLeave: hooks.onRequestLeave,
          mobileSearchOpen: hooks.mobileSearchOpen,
          onToggleMobileSearch: hooks.onToggleMobileSearch,
          filter: hooks.filter,
          onFilter: hooks.onFilter,
          onStartCall: _startCall,
          confirmedFingerprints: _confirmedFingerprints,
          onConfirmFingerprint: _confirmFingerprint,
        ),
      );

  Future<void> _startCall() async {
    final error = await startVoiceCall(ref, widget.sessionId);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(readableError(error))),
    );
  }

  void _confirmFingerprint() => setState(
        () => _confirmedFingerprints = {
          ..._confirmedFingerprints,
          widget.sessionId,
        },
      );

  /// The session is gone, so its confirmation no longer means anything.
  void _forgetConfirmation() {
    if (!mounted) return;
    setState(() => _confirmedFingerprints = {..._confirmedFingerprints}
      ..remove(widget.sessionId));
  }
}
