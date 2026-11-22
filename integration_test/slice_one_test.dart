// S5: slice-one moment-of-truth integration test (ADR 0013 close-out).
//
// Runs on a real desktop target against the actual `mosh_core.dll` (built via
// cargokit when `flutter test integration_test -d windows` runs). Unlike the
// widget suite, integration_test executes on the real platform, so RustLib
// init + FFI works. The test exercises the slice-one flow end-to-end
// through the two bridge surfaces -- the BridgeFacade for the 1:1 mirrors
// (diagnostics, runtime status, session list, invite mint, ADR 0025) and
// RealBridgeGateway for the conversation seam (leave) -- proving the whole
// stack (frb bindings, both surfaces, Rust runtime) is wired correctly with
// the real backend.
//
// Moss-absent graceful path: createInvite needs Moss running (moss.dll built
// via `moss:prepare`). If Moss is not present in the dev/CI env, the Rust
// side returns a ConversationBridgeError rather than crashing, and the
// invite-shape checks are skipped. The test must NOT fail the build when
// Moss is absent -- it asserts graceful behaviour either way.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError;
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/gateway/real_bridge_gateway.dart';
import 'package:mosh/src/rust/frb_generated.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // frb 2.x: initialize the bridge before any api call. integration_test
  // runs on the real platform so the cdylib loads; this is the call the
  // widget suite cannot make.
  setUpAll(() async {
    await RustLib.init();
  });

  testWidgets('slice-one end-to-end: diagnostics + runtime + list + invite',
      (tester) async {
    final bridge = BridgeFacade();
    final gateway = RealBridgeGateway();

    // 1. appDiagnostics(): the 4 const fields come from mosh_core
    //    api::diagnostics. appName is the Rust const "Mosh".
    final diag = await bridge.appDiagnostics();
    expect(diag.appName, 'Mosh');
    expect(diag.privacyModel, isNotEmpty);
    expect(diag.discoveryModel, isNotEmpty);
    expect(diag.mossLinkMode, isNotEmpty);

    // 2. nativeRuntimeStatus(): must complete without throwing. Moss may or
    //    may not load depending on the dev env; the call is honest either
    //    way. The five sub-structs are non-opaque across flutter_rust_bridge
    //    (FU-1), so the fields are real Dart getters; we still only assert
    //    reachability here (plus a real field read on moss) -- the call
    //    completing is the proof the runtime layer is wired.
    final status = await bridge.nativeRuntimeStatus();
    expect(status.moss.linkMode, isNotEmpty);

    // 3. listSessions(): completes with a snapshot (initially empty on a
    //    fresh runtime, or whatever a warm runtime has). Not asserting
    //    emptiness keeps the test order-independent.
    await bridge.listSessions();

    // 4. createInvite(): needs Moss running. If Moss is absent the Rust side
    //    returns a ConversationBridgeError (not a crash) and the invite-shape
    //    checks are skipped. If Moss is present, assert the real invite URI
    //    and fingerprint. This branch keeps the build green without Moss.
    try {
      final invite = await bridge.createInvite(
        request: const StartSessionRequest(
          displayName: 'slice-one-test',
          listenPort: 0,
        ),
      );
      expect(invite.inviteUri, startsWith('mosh://'));
      expect(invite.fingerprint, isNotEmpty);
      expect(invite.sessionId, isNotEmpty);

      // Tear down the session we just created so the runtime stays clean.
      await gateway.leave(DmTarget(invite.sessionId));
    } on ConversationBridgeError {
      // Moss absent (moss.dll not built via moss:prepare): the facade reports
      // a typed error. A panic or a wrong invite shape still fails the test.
    }
  });
}
