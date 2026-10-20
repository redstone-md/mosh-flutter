import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/voice_call_host.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import '../../support/message_builders.dart';
import '../../support/native_call_fixture.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import '../../support/settings.dart';
import '../../support/voice_recorder.dart';

void main() {
  testWidgets(
      'Android renders native video; dialogs and Back preserve the call',
      (tester) async {
    VoiceRecorderProbe(tester);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gateway = ScriptableGateway()
      ..seedSessions([
        TestSnapshots.dm(
            sessionId: 'dm', activeCall: TestCalls.active(callId: 'call')),
      ]);
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    for (var i = 0; i < 20; i++) {
      bridge.respondNext(
          BridgeMethod.nativeCallSnapshot, Future.value(nativeCallSnapshot()));
    }
    bridge.respondNext(
        BridgeMethod.nativeCallFrame,
        Future.value(native.Frame(
          sessionId: 'dm',
          callId: 'call',
          local: false,
          sequence: BigInt.one,
          width: 2,
          height: 2,
          sourceAgeMs: 0,
          pixels: Uint8List.fromList(List.generate(16, (_) => 255)),
        )));
    final owner = NativeCallOwner(bridge, () async => true);
    final container = ProviderContainer(overrides: [
      ...settingsAudioOverrides(),
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
      nativeCallOwnerProvider.overrideWithValue(owner),
    ]);
    addTearDown(container.dispose);
    final router = await pumpRoute(tester, AppRoutes.dmFor('dm'),
        container: container, settle: false);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.byType(VoiceCallHost), findsOneWidget);
    expect(tester.widget<CallView>(find.byType(CallView)).compact, false);
    expect(find.byType(RawImage), findsWidgets);
    expect(find.byTooltip('Turn camera on'), findsOneWidget);
    expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 1);

    await tester.tap(find.byTooltip('Call devices'));
    await tester.pumpAndSettle();
    expect(find.byType(MoshSelect<String?>), findsNWidgets(3));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MoshSelect<String?>), findsNothing);
    expect(tester.widget<CallView>(find.byType(CallView)).compact, false);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<CallView>(find.byType(CallView)).compact, true);
    expect(bridge.countOf(BridgeMethod.callEnd), 0);
    expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    owner.dispose();
    router.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
