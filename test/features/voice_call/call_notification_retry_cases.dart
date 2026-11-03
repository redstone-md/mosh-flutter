import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/voice_call_layer.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/notifications_provider.dart';
import '../../support/call_notifications.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

void main() {
  for (final posted in [true, false]) {
    testWidgets('failed accept retries notification; initially posted: $posted',
        (tester) async {
      final gateway = ScriptableGateway()
        ..seedSessions([
          TestSnapshots.dm(
              sessionId: 'origin',
              pendingCall: const PendingCall(
                  answerPending: false, callId: 'call', fromDevice: 'Alice'))
        ]);
      final accepted = Completer<void>();
      final bridge = ScriptableBridge(conversations: gateway.conversations)
        ..respondNext(BridgeMethod.callAccept, accepted.future);
      final notifications = RecordingCallNotifications();
      final ready = Completer<bool>();
      if (posted) ready.complete(true);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const manager = MethodChannel('window_manager');
      messenger.setMockMethodCallHandler(
          manager, (call) async => call.method == 'isFocused' ? false : null);
      addTearDown(() => messenger.setMockMethodCallHandler(manager, null));
      final container = ProviderContainer(overrides: [
        gatewayProvider.overrideWithValue(gateway),
        bridgeFacadeProvider.overrideWithValue(bridge),
        notificationsReadyProvider.overrideWith((_) => ready.future),
        flutterLocalNotificationsPluginProvider
            .overrideWithValue(notifications),
      ]);
      addTearDown(container.dispose);
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      await pumpScreen(
          tester, Scaffold(body: VoiceCallLayer(sessionId: 'origin', l: l)),
          container: container, settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(notifications.showCalls, posted ? 1 : 0);
      await tester.tap(find.byTooltip('Accept call'));
      await tester.pump();
      if (posted) expect(notifications.cancelled, [notifications.lastId]);
      accepted.completeError(StateError('accept failed'));
      await tester.pump();
      if (!posted) ready.complete(true);
      await tester.pump(const Duration(milliseconds: 50));
      expect(notifications.showCalls, posted ? 2 : 1);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump();
    });
  }
}
