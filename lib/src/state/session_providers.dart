// S4.0: Riverpod server-state providers for the slice-one Gateway surface.
//
// The DM LIST is not one of them: [conversationListProvider] serves all
// three kinds, so the kind branch lives in one module
// (`conversation_providers.dart`).
//
// Per ADR 0010: server/async state lives in AsyncNotifierProvider / FutureProvider
// (the TanStack-Query analogue — loading/data/error via AsyncValue<T>). The
// diagnostics reads and the invite mint are 1:1 bridge mirrors, so they go
// through `bridgeFacadeProvider` (ADR 0025); the conversation seam (the DM
// poll below) goes through `gatewayProvider` (ADR 0013). Ephemeral
// cross-screen UI state (the invite-create flow) lives in a sync Notifier here
// because it spans onboarding + invite-paste screens.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';

/// Server state: app identity diagnostics (diagnostics screen, S4.8).
final diagnosticsProvider =
    AsyncNotifierProvider<DiagnosticsNotifier, AppDiagnostics>(
  DiagnosticsNotifier.new,
);

class DiagnosticsNotifier extends AsyncNotifier<AppDiagnostics> {
  @override
  Future<AppDiagnostics> build() =>
      ref.watch(bridgeFacadeProvider).appDiagnostics();
}

/// Server state: native runtime readiness (diagnostics screen, S4.8).
/// Routed through the `bridgeFacadeProvider` seam (ADR 0025) so the screen
/// renders real field values under both the test bridge and the real facade.
/// The five `NativeRuntimeStatus` sub-structs are non-opaque across
/// flutter_rust_bridge, so both return constructible, field-readable values
/// (no `<opaque>` fallback).
final nativeRuntimeStatusProvider = FutureProvider<NativeRuntimeStatus>(
    (ref) => ref.watch(bridgeFacadeProvider).nativeRuntimeStatus());

/// Server state: what the loaded moss library reports about itself --
/// version, the active DM counterpart's last measured RTT, the field log's
/// file (spec #5). The family arg is the counterpart's moss peer id, or
/// null when there is no single counterpart (channel/group drawers, no
/// session): a null asks about the library alone, and the RTT comes back
/// honestly unknown. One read per watch, like every facade mirror.
final mossLibraryInfoProvider =
    FutureProvider.family<MossLibraryInfo, String?>((ref, peerMossId) {
  return ref.watch(bridgeFacadeProvider).mossLibraryInfo(
        peerMossId: peerMossId,
      );
});

/// Ephemeral cross-screen UI state for the invite-create flow (onboarding sets
/// displayName; invite-paste reads it). ADR 0010 allows widget-local state,
/// but this flow spans screens, so a sync NotifierProvider is justified.
final inviteFlowProvider =
    NotifierProvider<InviteFlowNotifier, InviteFlowState>(
        InviteFlowNotifier.new);

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

  /// What we call ourselves on the wire when onboarding never set a name.
  /// A peer identity, not UI text, so it is not localized.
  String get senderDisplayName =>
      displayName.isEmpty ? 'anonymous' : displayName;

  /// A nullable field needs a sentinel to tell "not passed" from "passed
  /// as null": with a plain `String? staticPeer` parameter, a reset
  /// (`staticPeer: null`) was indistinguishable from "keep the old
  /// value" (`?? this.staticPeer`), so a static peer could never be
  /// cleared — only overwritten. The sentinels make the reset explicit;
  /// the fields themselves stay plain and optional.
  static const Object _unset = Object();

  InviteFlowState copyWith({
    String? displayName,
    int? listenPort,
    Object? staticPeer = _unset,
    Object? lastInvite = _unset,
  }) =>
      InviteFlowState(
        displayName: displayName ?? this.displayName,
        listenPort: listenPort ?? this.listenPort,
        staticPeer:
            staticPeer == _unset ? this.staticPeer : staticPeer as String?,
        lastInvite: lastInvite == _unset
            ? this.lastInvite
            : lastInvite as InviteCreated?,
      );
}

class InviteFlowNotifier extends Notifier<InviteFlowState> {
  @override
  InviteFlowState build() => const InviteFlowState();

  void setDisplayName(String value) =>
      state = state.copyWith(displayName: value);
  void setListenPort(int value) => state = state.copyWith(listenPort: value);
  void setStaticPeer(String? value) =>
      state = state.copyWith(staticPeer: value);

  /// Clears invite results when the user starts a fresh onboarding flow.
  void resetInviteState() {
    state = InviteFlowState(
      displayName: state.displayName,
      listenPort: state.listenPort,
      staticPeer: state.staticPeer,
    );
  }

  /// Calls bridgeFacadeProvider.createInvite, stores the result, and returns
  /// it so the caller can navigate to the invite-paste screen with the URI
  /// in hand.
  Future<InviteCreated> create() async {
    final invite = await ref.read(bridgeFacadeProvider).createInvite(
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
final activeSessionProvider = FutureProvider.family<SessionSnapshot, String>(
  (ref, sessionId) => ref.watch(gatewayProvider).poll(DmTarget(sessionId)),
);
