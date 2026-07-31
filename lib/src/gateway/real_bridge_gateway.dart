// S5: the slice-one moment-of-truth backend (ADR 0013 close-out).
//
// RealBridgeGateway delegates every Gateway method to the corresponding
// flutter_rust_bridge-generated free function in `lib/src/rust/api/`. It is
// a thin pass-through: no caching, no logic, no shaping -- the same surface
// FakeGateway mocked, now backed by the real `mosh_core` runtime. Widgets
// keep consuming `Gateway` via `gatewayProvider`; this class only exists to
// be swapped in as the default by the provider's `MOSH_FAKE_GATEWAY` flag.
//
// Lifecycle note: every method assumes `RustLib.init()` has run (main.dart
// calls it on startup; the integration test calls it explicitly). Calling
// before init throws via the frb generated `RustLib.instance.api` indirection
// -- which is exactly the behaviour the Fake could not reproduce.

import 'package:mosh/src/gateway/gateway.dart';
// diagnostics.dart defines both the AppDiagnostics/NativeRuntimeStatus types
// and the appDiagnostics()/nativeRuntimeStatus() free functions. The function
// names collide with this class's own method names, so import the functions
// under the `api` prefix while pulling the types in unqualified.
import 'package:mosh/src/rust/api/diagnostics.dart' show AppDiagnostics, NativeRuntimeStatus;
import 'package:mosh/src/rust/api/diagnostics.dart' as api show appDiagnostics, nativeRuntimeStatus;
// private_dm.dart defines only free functions (no types); prefix them so
// they don't shadow the interface method names.
import 'package:mosh/src/rust/api/private_dm.dart' as api show acceptInvite, closeSession, createInvite, listSessions, pollSession, sendMessage;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// Real `mosh_core`-backed Gateway. See file doc for the lifecycle contract.
class RealBridgeGateway implements Gateway {
  @override
  Future<AppDiagnostics> appDiagnostics() => api.appDiagnostics();

  @override
  Future<NativeRuntimeStatus> nativeRuntimeStatus() =>
      api.nativeRuntimeStatus();

  @override
  Future<InviteCreated> createInvite({required StartSessionRequest request}) =>
      api.createInvite(request: request);

  @override
  Future<SessionSnapshot> acceptInvite({required AcceptInviteRequest request}) =>
      api.acceptInvite(request: request);

  @override
  Future<SendMessageResult> sendMessage({
    required String sessionId,
    required String body,
  }) => api.sendMessage(sessionId: sessionId, body: body);

  @override
  Future<SessionSnapshot> pollSession({required String sessionId}) =>
      api.pollSession(sessionId: sessionId);

  @override
  Future<SessionListSnapshot> listSessions() => api.listSessions();

  @override
  Future<CloseSessionResult> closeSession({required String sessionId}) =>
      api.closeSession(sessionId: sessionId);
}
