// S4.0: Riverpod server-state providers for the slice-one Gateway surface.
//
// Per ADR 0010: server/async state lives in AsyncNotifierProvider / FutureProvider
// (the TanStack-Query analogue — loading/data/error via AsyncValue<T>). All
// providers consume the `gatewayProvider` seam (ADR 0013), never a concrete
// Gateway, so S5 swaps fake->real by editing gatewayProvider only. Ephemeral
// cross-screen UI state (the invite-create flow) lives in a sync Notifier here
// because it spans onboarding + invite-paste screens.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';

/// Server state: the list of all DM sessions (sessions screen, S4.4).
/// `AsyncValue<SessionListSnapshot>` — loading -> data/error per ADR 0010.
final sessionListProvider =
    AsyncNotifierProvider<SessionListNotifier, SessionListSnapshot>(
  SessionListNotifier.new,
);

class SessionListNotifier extends AsyncNotifier<SessionListSnapshot> {
  @override
  Future<SessionListSnapshot> build() =>
      ref.watch(gatewayProvider).listSessions();

  /// Re-run the server query after a mutation (createInvite/sendMessage).
  Future<void> refresh() async => state = await AsyncValue.guard(
        () => ref.read(gatewayProvider).listSessions(),
      );
}

/// Server state: app identity diagnostics (diagnostics screen, S4.8).
/// appDiagnostics() works under the FakeGateway; nativeRuntimeStatus does not
/// (opaque sub-structs), so no provider is offered for it here.
final diagnosticsProvider =
    AsyncNotifierProvider<DiagnosticsNotifier, AppDiagnostics>(
  DiagnosticsNotifier.new,
);

class DiagnosticsNotifier extends AsyncNotifier<AppDiagnostics> {
  @override
  Future<AppDiagnostics> build() =>
      ref.watch(gatewayProvider).appDiagnostics();
}

/// Ephemeral cross-screen UI state for the invite-create flow (onboarding sets
/// displayName; invite-paste reads it). ADR 0010 allows widget-local state,
/// but this flow spans screens, so a sync NotifierProvider is justified.
final inviteFlowProvider =
    NotifierProvider<InviteFlowNotifier, InviteFlowState>(InviteFlowNotifier.new);

class InviteFlowState {
  const InviteFlowState({
    this.displayName = '',
    this.listenPort = 8765,
    this.staticPeer,
    this.lastInvite,
  });

  final String displayName;
  final int listenPort;
  final String? staticPeer;
  final InviteCreated? lastInvite;

  InviteFlowState copyWith({
    String? displayName,
    int? listenPort,
    String? staticPeer,
    InviteCreated? lastInvite,
  }) =>
      InviteFlowState(
        displayName: displayName ?? this.displayName,
        listenPort: listenPort ?? this.listenPort,
        staticPeer: staticPeer ?? this.staticPeer,
        lastInvite: lastInvite ?? this.lastInvite,
      );
}

class InviteFlowNotifier extends Notifier<InviteFlowState> {
  @override
  InviteFlowState build() => const InviteFlowState();

  void setDisplayName(String value) =>
      state = state.copyWith(displayName: value);
  void setListenPort(int value) =>
      state = state.copyWith(listenPort: value);
  void setStaticPeer(String? value) =>
      state = state.copyWith(staticPeer: value);

  /// Calls gateway.createInvite, stores the result, and returns it so the
  /// caller can navigate to the invite-paste screen with the URI in hand.
  Future<InviteCreated> create() async {
    final invite = await ref.read(gatewayProvider).createInvite(
          request: StartSessionRequest(
            displayName: state.displayName,
            listenPort: state.listenPort,
            staticPeer: state.staticPeer,
          ),
        );
    state = state.copyWith(lastInvite: invite);
    return invite;
  }
}

/// Server state: one session's snapshot, parameterized by sessionId (DM
/// screen, S4.6). A one-shot read per watch; the DM screen re-polls by
/// re-reading on a timer or invalidating. FutureProvider.family is the v3
/// idiom for a parameterized async read.
final activeSessionProvider =
    FutureProvider.family<SessionSnapshot, String>(
  (ref, sessionId) => ref.watch(gatewayProvider).pollSession(sessionId: sessionId),
);
