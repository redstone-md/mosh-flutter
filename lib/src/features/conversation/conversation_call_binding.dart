/// The call capability a conversation hosts but does not own.
///
/// A DM can carry a call; the conversation module does not know how. It
/// declares the slots a call needs -- start one, and somewhere to hang the
/// overlay -- and the composition root fills them from the voice-call
/// module. Nothing here imports that module, so the conversation module
/// stays independent of it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';

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
    required this.overlay,
  });

  final ConversationCallStarter start;

  final ConversationCallOverlay overlay;
}

/// The bound call module, or null when nothing has bound one: a
/// conversation then starts no call and hangs no overlay, which is what
/// every test that does not bind it gets.
final conversationCallBindingProvider = Provider<ConversationCallBinding?>(
  (ref) => null,
);
