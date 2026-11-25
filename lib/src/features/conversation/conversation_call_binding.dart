import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';

/// What a conversation hands the overlay it hosts: its identity, its
/// strings, and where an error goes.
class ConversationCallHost {
  const ConversationCallHost({
    required this.conversationId,
    required this.l,
    required this.onError,
  });

  /// The conversation's id -- a DM's session id.
  final String conversationId;

  /// The localizations the overlay renders with.
  final AppLocalizations l;

  /// The conversation's inline error setter. Audio-setup failures land
  /// here; call-control failures stay transient feedback inside the call.
  final void Function(String? message)? onError;
}

/// Starts a call on [conversationId]. Resolves to the error to surface, or
/// to null when the call started.
typedef ConversationCallStarter = Future<Object?> Function(
  WidgetRef ref,
  String conversationId,
);

/// Builds the overlay a conversation stacks over its body. The overlay
/// draws nothing until there is a call; the conversation only gives it
/// somewhere to live.
typedef ConversationCallOverlay = Widget Function(
  BuildContext context,
  ConversationCallHost host,
);

/// The two slots a conversation offers the call module.
class ConversationCallBinding {
  const ConversationCallBinding({
    required this.start,
    this.startVideo,
    required this.overlay,
  });

  final ConversationCallStarter start;
  final ConversationCallStarter? startVideo;

  final ConversationCallOverlay overlay;
}

/// The bound call module, or null when nothing has bound one: a
/// conversation then starts no call and hangs no overlay, which is what
/// every test that does not bind it gets.
final conversationCallBindingProvider = Provider<ConversationCallBinding?>(
  (ref) => null,
);

/// Starts a call on the DM [sessionId] through the bound call module and
/// reports what it could not do. Does nothing when no module is bound, or
/// when it offers no video for a [video] call.
Future<void> startConversationCall(
    WidgetRef ref, BuildContext context, String sessionId,
    {bool video = false}) async {
  final call = ref.read(conversationCallBindingProvider);
  final start = video ? call?.startVideo : call?.start;
  if (start == null) return;
  final reportError = actionErrorReporter(context);
  final error = await start(ref, sessionId);
  if (error != null) reportError(error);
}
