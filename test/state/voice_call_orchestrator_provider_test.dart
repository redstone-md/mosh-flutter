// Tests for the voice-call orchestrator provider. Each test wires a
// ProviderContainer that overrides activeSessionProvider with a mutable
// controller, bridgeFacadeProvider with a scripted bridge and, where media
// matters, the native call owner. The orchestrator's binding is
// fire-and-forget (async); a listen(...) keeps the provider alive so it
// rebuilds when the watched async provider resolves.
library;

import 'dart:async';

import 'package:mosh/src/state/native_call_owner_provider.dart';
import '../support/native_call_fixture.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/features/voice_call/incoming_call_modal.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import '../support/scriptable_bridge.dart';
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import 'package:mosh/src/state/session_providers.dart'
    show activeSessionProvider;
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';

part 'voice_call_orchestrator_provider_support.dart';
part 'voice_call_native_binding_support.dart';

void main() {
  registerNativeBindingTests();
  group('voice_call_orchestrator_provider', () {
    test('no ActiveCall -> no orchestrator, muted false', () async {
      final gateway = ScriptableBridge();
      final controller = _SessionController(_session('sess-1'));
      final container = _container(controller: controller, gateway: gateway);
      addTearDown(container.dispose);

      final sub = _subscribe(container);
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
          container.read(voiceCallOrchestratorProvider('sess-1')).muted, false);
    });

    test('dialog derives from the snapshot (pending/outgoing/active/none)',
        () async {
      // Pending -> IncomingCallDialog (peer from fromDevice).
      final pendingController = _SessionController(_session(
        'sess-1',
        pendingCall:
            PendingCall(answerPending: false, callId: 'p1', fromDevice: 'Bob'),
      ));
      final pendingContainer = _container(
        controller: pendingController,
        gateway: ScriptableBridge(),
      );
      addTearDown(pendingContainer.dispose);
      final pendingSub = pendingContainer.listen(
          voiceCallOrchestratorProvider('sess-1'), (_, __) {},
          fireImmediately: true);
      addTearDown(pendingSub.close);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final pendingDialog =
          pendingContainer.read(voiceCallOrchestratorProvider('sess-1')).dialog;
      expect(pendingDialog, isA<IncomingCallDialog>());
      expect(pendingDialog.callId, 'p1');
      expect(pendingDialog.peerName, 'Bob');

      // Outgoing -> OutgoingCallDialog (peer from peerDisplayName).
      final outgoingController = _SessionController(_session(
        'sess-1',
        outgoingCall: const OutgoingCall(callId: 'o1'),
      ));
      final outgoingContainer = _container(
        controller: outgoingController,
        gateway: ScriptableBridge(),
      );
      addTearDown(outgoingContainer.dispose);
      final outgoingSub = outgoingContainer.listen(
          voiceCallOrchestratorProvider('sess-1'), (_, __) {},
          fireImmediately: true);
      addTearDown(outgoingSub.close);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final outgoingDialog = outgoingContainer
          .read(voiceCallOrchestratorProvider('sess-1'))
          .dialog;
      expect(outgoingDialog, isA<OutgoingCallDialog>());
      expect(outgoingDialog.callId, 'o1');
      expect(outgoingDialog.peerName, 'Alice');

      // Active -> ActiveCallDialog.
      final activeController =
          _SessionController(_session('sess-1', activeCall: _activeCall('a1')));
      final activeContainer = _container(
        controller: activeController,
        gateway: ScriptableBridge(),
      );
      addTearDown(activeContainer.dispose);
      final activeSub = activeContainer.listen(
          voiceCallOrchestratorProvider('sess-1'), (_, __) {},
          fireImmediately: true);
      addTearDown(activeSub.close);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final activeDialog =
          activeContainer.read(voiceCallOrchestratorProvider('sess-1')).dialog;
      expect(activeDialog, isA<ActiveCallDialog>());
      expect(activeDialog.callId, 'a1');

      // None -> NoCallDialog.
      final noneController = _SessionController(_session('sess-1'));
      final noneContainer = _container(
        controller: noneController,
        gateway: ScriptableBridge(),
      );
      addTearDown(noneContainer.dispose);
      final noneSub = noneContainer.listen(
          voiceCallOrchestratorProvider('sess-1'), (_, __) {},
          fireImmediately: true);
      addTearDown(noneSub.close);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        noneContainer.read(voiceCallOrchestratorProvider('sess-1')).dialog,
        isA<NoCallDialog>(),
      );
    });

    test('clearError clears the surfaced error and is idempotent', () async {
      final gateway = ScriptableBridge()
        ..failNext(BridgeMethod.nativeCallPrepare);
      final owner = NativeCallOwner(gateway, () async => false);
      addTearDown(owner.dispose);
      final controller =
          _SessionController(_session('sess-1', activeCall: _activeCall('a')));
      final container =
          _container(controller: controller, gateway: gateway, native: owner);
      addTearDown(container.dispose);

      final sub = _subscribe(container);
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        container.read(voiceCallOrchestratorProvider('sess-1')).error,
        isNotNull,
      );

      container
          .read(voiceCallOrchestratorProvider('sess-1').notifier)
          .clearError();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(
        container.read(voiceCallOrchestratorProvider('sess-1')).error,
        isNull,
      );

      // Clearing again with no error is a no-op (no throw, no new error).
      container
          .read(voiceCallOrchestratorProvider('sess-1').notifier)
          .clearError();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(
        container.read(voiceCallOrchestratorProvider('sess-1')).error,
        isNull,
      );
    });

    test('endCall for the same call twice is a single gateway.callEnd',
        () async {
      final gateway = ScriptableBridge();
      final controller =
          _SessionController(_session('sess-1', activeCall: _activeCall('a')));
      final container = _container(controller: controller, gateway: gateway);
      addTearDown(container.dispose);

      final sub = _subscribe(container);
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final notifier =
          container.read(voiceCallOrchestratorProvider('sess-1').notifier);
      await notifier.endCall('a', kCallDeclineReasonHangup);
      await notifier.endCall('a', kCallDeclineReasonHangup);

      expect(gateway.countOf(BridgeMethod.callEnd), 1);
    });

    test(
        'incoming no-answer timeout is pinned to 30s (pairs with 45s Rust ring budget)',
        () {
      // The callee's no-answer budget (Dart) is deliberately SHORTER than the
      // caller's ring budget (Rust CALL_RING_TIMEOUT_MS = 45000). On a healthy
      // link the callee's real decline reaches the caller before the caller
      // gives up on its own, so the budget is only a backstop for a lost
      // decline. Change the two together -- see incoming_call_modal.dart.
      expect(kIncomingNoAnswerTimeout, const Duration(milliseconds: 30000));
    });
  });
}
