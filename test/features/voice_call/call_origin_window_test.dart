import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/main.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/features/voice_call/call_modal_card.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import '../../support/message_builders.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import '../../support/settings.dart';

void main() {
  testWidgets('opening the call origin restores a minimized main window',
      (tester) async {
    const manager = MethodChannel('window_manager');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    var minimized = true;
    messenger.setMockMethodCallHandler(manager, (call) async {
      if (['restore', 'show', 'focus'].contains(call.method)) {
        calls.add(call.method);
      }
      if (call.method == 'restore') minimized = false;
      if (call.method.startsWith('is')) return false;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(manager, null));
    final gateway = ScriptableGateway()
      ..seedSessions([
        TestSnapshots.dm(
            sessionId: 'origin',
            peerDisplayName: 'Alice',
            outgoingCall: const OutgoingCall(callId: 'call'))
      ]);
    final container = ProviderContainer(overrides: [
      ...settingsAudioOverrides(),
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(
          ScriptableBridge(conversations: gateway.conversations)),
      firstRunEnabledProvider.overrideWithValue(false),
    ]);
    addTearDown(container.dispose);
    appRouter.go(AppRoutes.settings);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MoshApp()));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.descendant(
        of: find.byType(CallModalCard), matching: find.text('Alice')));
    await tester.pump();
    expect(minimized, isFalse);
    expect(calls, ['restore', 'show', 'focus']);
    expect(appRouter.routeInformationProvider.value.uri.path,
        AppRoutes.dmFor('origin'));
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
    appRouter.go(AppRoutes.sessions);
  });
}
