import 'dart:async';
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
  for (final (action, delayed) in [
    ('accept', false),
    ('decline', false),
    ('remote', false),
    ('remote', true),
    ('dispose', true)
  ]) {
    testWidgets(
        'incoming notification is removed: $action, delayed show: $delayed',
        (tester) async {
      final gateway = ScriptableGateway()
        ..seedSessions([
          TestSnapshots.dm(
              sessionId: 'origin',
              pendingCall:
                  const PendingCall(callId: 'call', fromDevice: 'Alice'))
        ]);
      final notifications = RecordingCallNotifications();
      if (delayed) notifications.pendingShow = Completer<void>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const manager = MethodChannel('window_manager');
      messenger.setMockMethodCallHandler(
          manager, (call) async => call.method == 'isFocused' ? false : null);
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
          tester, Scaffold(body: VoiceCallLayer(sessionId: 'origin', l: l)),
          container: container, settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(notifications.showCalls, 1);
      if (action == 'accept' || action == 'decline') {
        await tester.tap(find
            .byTooltip(action == 'accept' ? 'Accept call' : 'Decline call'));
      } else if (action == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        gateway.seedSessions([TestSnapshots.dm(sessionId: 'origin')]);
        container.invalidate(conversationListProvider(ConversationKind.dm));
        container.invalidate(activeSessionProvider('origin'));
      }
      await tester.pump();
      notifications.pendingShow?.complete();
      await tester.pump(const Duration(milliseconds: 50));
      expect(notifications.cancelled, [notifications.lastId]);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump();
    });
  }
}
