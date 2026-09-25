// The app-wide auto-poll loop.
//
// Why this exists: `mosh_core` exposes NO StreamSink. Every Rust read entry
// point (`private_dm::list_sessions` / `poll_session`, `channel::list` /
// `poll`, `private_group::list` / `poll`) starts with `drain_inbound()` --
// the poll IS what pulls frames off the moss queue and advances the MLS
// handshake. With no periodic caller, the runtime only advanced when a
// mutation happened to invalidate a provider, which is why a fresh session
// stayed "connecting" until BOTH sides sent, and why peer messages only
// appeared after a local send.
//
// Shape: one process-lifetime `Timer.periodic`. Each tick refreshes every
// conversation kind's list. Each kind has its own in-flight guard: a slow
// kind skips its own ticks and never holds the other kinds back (a DM
// runtime busy with a transfer used to freeze the channel and group lists
// too). The open conversation's snapshot is re-read when its kind's list
// read finishes, so it never queues behind that read.
//
// The DM protocol itself no longer depends on this loop: a Rust service
// thread drives it (`api::private_dm`). This loop keeps the screens fresh.
//
// The list entries use their own `refresh()` (a guard-swap that never
// publishes `AsyncLoading`), so the rail does not flicker. The snapshot
// families are `FutureProvider.family`, so their reload does publish
// `AsyncLoading` with the previous value attached -- the chat screens pass
// `skipLoadingOnReload: true` to `.when` so a reload renders the retained
// data instead of a spinner.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/active_conversation_key_provider.dart'
    show activeConversationProvider;
import 'package:mosh/src/state/conversation_providers.dart'
    show conversationListProvider, invalidateConversation;

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
  final inFlight = <ConversationKind>{};

  // The open conversation's snapshot follows its own kind's list read: it
  // never queues behind that read, and a stuck kind never piles up
  // snapshot reads.
  void refreshOpenSnapshot(ConversationKind kind) {
    if (!ref.mounted) return;
    final active = ref.read(activeConversationProvider);
    if (active == null || active.conversation.kind != kind) return;
    invalidateConversation(ref.invalidate, active.conversation);
  }

  void refresh(ConversationKind kind) {
    if (!inFlight.add(kind)) return;
    unawaited(ref
        .read(conversationListProvider(kind).notifier)
        .refresh()
        .whenComplete(() {
      inFlight.remove(kind);
      refreshOpenSnapshot(kind);
    }));
  }

  final timer =
      Timer.periodic(interval, (_) => ConversationKind.values.forEach(refresh));
  ref.onDispose(timer.cancel);
});
