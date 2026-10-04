import 'dart:async';
import 'package:mosh/src/state/chat_names_provider.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/platform/foreground_poller.dart';

import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/active_conversation_key_provider.dart'
    show activeConversationProvider;
import 'package:mosh/src/state/conversation_providers.dart'
    show ConversationList, conversationListProvider, invalidateConversation;

/// Poll cadence -- 1 second.
const Duration kAutoPollInterval = Duration(milliseconds: 1000);

/// The cadence [autoPollProvider] runs at, or null to not poll at all.
/// Defaults to null so `flutter test` never inherits a live timer; the
/// production root binds [kAutoPollInterval] via `productionOverrides`
/// (the same seam the voice factories use).
final autoPollIntervalProvider = Provider<Duration?>((ref) => null);

/// Owns the auto-poll timer. Watch it once from the app root so it lives
/// for the process; the timer is cancelled when the scope is disposed.
final autoPollProvider = Provider<void>((ref) {
  final interval = ref.watch(autoPollIntervalProvider);
  if (interval == null) return;
  late ForegroundPoller poller;

  // The open conversation's snapshot follows its own kind's list read: it
  // never queues behind that read, and a stuck kind never piles up
  // snapshot reads.
  void refreshOpenSnapshot(ConversationKind kind) {
    if (!ref.mounted || !poller.isForeground) return;
    final active = ref.read(activeConversationProvider);
    if (active == null || active.conversation.kind != kind) return;
    invalidateConversation(ref.invalidate, active.conversation);
  }

  for (final kind in ConversationKind.values) {
    ref.listen(conversationListProvider(kind), (before, next) {
      if (next is AsyncData<ConversationList> && before != next) {
        refreshOpenSnapshot(kind);
      }
    });
  }

  poller = ForegroundPoller(interval, () {
    unawaited(ref.read(chatNamesProvider.notifier).refresh());
    for (final kind in ConversationKind.values) {
      unawaited(ref
          .read(conversationListProvider(kind).notifier)
          .refresh(background: true));
    }
  });
  ref.onDispose(poller.dispose);
});
