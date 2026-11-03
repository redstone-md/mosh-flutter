import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/voice_call_layer.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/notifications_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import '../../support/call_notifications.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

void main() {
  for (final window in ['main', 'call', 'main failure', 'call failure']) {
    for (final ended in [false, true]) {
      testWidgets('incoming alert follows $window blur; ended: $ended',
          (tester) async {
        var mainFocused = window.startsWith('main');
        var callFocused = window.startsWith('call');
        var failFocus = false;
        final gateway = ScriptableGateway()
          ..seedSessions([
            TestSnapshots.dm(
                sessionId: 'origin',
                pendingCall: const PendingCall(
                    answerPending: false, callId: 'call', fromDevice: 'Alice'))
          ]);
        final notifications = RecordingCallNotifications();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const manager = MethodChannel('window_manager');
        messenger.setMockMethodCallHandler(manager, (call) async {
          if (call.method != 'isFocused') return null;
          if (failFocus && window == 'main failure') {
            throw PlatformException(code: 'focus unavailable');
          }
          return mainFocused;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(manager, null));
        final container = ProviderContainer(overrides: [
          gatewayProvider.overrideWithValue(gateway),
          bridgeFacadeProvider.overrideWithValue(
              ScriptableBridge(conversations: gateway.conversations)),
          notificationsReadyProvider.overrideWith((_) async => true),
          flutterLocalNotificationsPluginProvider
              .overrideWithValue(notifications),
        ]);
        addTearDown(container.dispose);
        final l = await AppLocalizations.delegate.load(const Locale('en'));
        await pumpScreen(
            tester,
            Scaffold(
                body: VoiceCallLayer(
              sessionId: 'origin',
              l: l,
              isCallWindowFocused: () async {
                if (failFocus && window == 'call failure') {
                  throw StateError('child focus unavailable');
                }
                return callFocused;
              },
            )),
            container: container,
            settle: false);
        await tester.pump(const Duration(milliseconds: 50));
        expect(notifications.showCalls, 0);
        if (ended) {
          gateway.seedSessions([TestSnapshots.dm(sessionId: 'origin')]);
          container.invalidate(conversationListProvider(ConversationKind.dm));
          container.invalidate(activeSessionProvider('origin'));
          await tester.pump(const Duration(milliseconds: 50));
        }
        mainFocused = false;
        callFocused = false;
        failFocus = true;
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump(const Duration(milliseconds: 50));
        expect(notifications.showCalls, ended ? 0 : 1);
        await tester.pump(const Duration(milliseconds: 1100));
        expect(notifications.showCalls, ended ? 0 : 1);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pump();
      });
    }
  }
}
