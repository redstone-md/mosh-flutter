// The app-wide auto-poll loop -- the Flutter port of React's
// `usePrivateDmSnapshots` interval (use-private-dm-snapshots.ts L139-149:
// `window.setInterval(() => void refresh(true), AUTO_POLL_MS)`).
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
// Shape: one process-lifetime `Timer.periodic` refreshing the three list
// providers in parallel (React's `Promise.all` of listPrivateSessions /
// listChannels / listPrivateGroups) plus the open conversation's snapshot
// family. `_inFlight` mirrors React's `pollInFlight` ref so a slow tick is
// skipped rather than queued.
//
// The three list notifiers use their own `refresh()` (a guard-swap that
// never publishes `AsyncLoading`), so the rail does not flicker. The
// snapshot families are `FutureProvider.family`, so their reload does
// publish `AsyncLoading` with the previous value attached -- the chat
// screens pass `skipLoadingOnReload: true` to `.when` so a reload renders
// the retained data instead of a spinner.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/session_providers.dart';

/// Poll cadence -- 1:1 with React's `AUTO_POLL_MS = 1000`.
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
  var inFlight = false;

  Future<void> tick() async {
    if (inFlight) return;
    inFlight = true;
    try {
      await Future.wait(<Future<void>>[
        ref.read(sessionListProvider.notifier).refresh(),
        ref.read(channelListProvider.notifier).refresh(),
        ref.read(groupListProvider.notifier).refresh(),
      ]);
      final active = ref.read(activeConversationProvider);
      if (active == null) return;
      switch (active.kind) {
        case ActiveConversationKind.dm:
          ref.invalidate(activeSessionProvider(active.arg));
        case ActiveConversationKind.channel:
          ref.invalidate(channelSnapshotProvider(active.arg));
        case ActiveConversationKind.group:
          ref.invalidate(groupSnapshotProvider(active.arg));
      }
    } finally {
      inFlight = false;
    }
  }

  final timer = Timer.periodic(interval, (_) => unawaited(tick()));
  ref.onDispose(timer.cancel);
});
