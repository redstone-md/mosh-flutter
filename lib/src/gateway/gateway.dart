// Sealed seam between the flutter_rust_bridge surface and the Flutter UI.
//
// `FakeGateway` (S4) and `RealBridgeGateway` (S5) both implement this interface;
// widgets depend on `Gateway`, never on a concrete impl, so swapping the
// wired runtime is one provider change (ADR 0013).
//
// The eight methods below mirror the slice-one Rust `mosh_core::api` surface
// 1:1, poll-based (no streams). Signatures match the generated frb functions.

import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// Abstraction over the slice-one private-DM + diagnostics API.
///
/// Implementations: `FakeGateway` (in-Dart, first slice only, ADR 0013) and
/// `RealBridgeGateway` (delegates to the generated frb functions, S5). Widgets
/// consume this interface, never a concrete class, so the wired backend is a
/// single Riverpod provider swap.
abstract interface class Gateway {
  Future<AppDiagnostics> appDiagnostics();
  Future<NativeRuntimeStatus> nativeRuntimeStatus();
  Future<InviteCreated> createInvite({required StartSessionRequest request});
  Future<SessionSnapshot> acceptInvite({required AcceptInviteRequest request});
  Future<SendMessageResult> sendMessage({required String sessionId, required String body});
  Future<SessionSnapshot> pollSession({required String sessionId});
  Future<SessionListSnapshot> listSessions();
  Future<CloseSessionResult> closeSession({required String sessionId});
}
