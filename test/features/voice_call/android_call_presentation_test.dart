import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:mosh/src/features/voice_call/android_call_presentation.dart';
import 'package:mosh/src/features/voice_call/floating_call_view.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/app/mosh_theme.dart';
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
    final messenger = tester.binding.defaultBinaryMessenger;
    final configurations = <MethodCall>[];
    messenger.setMockMethodCallHandler(AndroidCallPresentation.channel,
        (call) async {
      configurations.add(call);
      return null;
    });
    final presentation = AndroidCallPresentation();
    addTearDown(() {
      presentation.dispose();
      messenger.setMockMethodCallHandler(AndroidCallPresentation.channel, null);
    });
    final container = ProviderContainer(overrides: [
      ...settingsAudioOverrides(),
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
      nativeCallOwnerProvider.overrideWithValue(owner),
      androidCallPresentationProvider.overrideWithValue(presentation),
    ]);
    addTearDown(container.dispose);
    final router = await pumpRoute(tester, AppRoutes.dmFor('dm'),
        container: container,
        settle: false,
        builder: (context, child) => Theme(data: moshThemeData, child: child!));
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
    expect(find.byType(FloatingCallView), findsOneWidget);
    final before = tester.getTopLeft(find.byType(FloatingCallView));
    await tester.drag(find.byType(FloatingCallView), const Offset(-80, 180));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(FloatingCallView)).dy,
        greaterThan(before.dy));
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingCallView), findsOneWidget);
    await tester.tap(find.byTooltip('Show call window'));
    await tester.pumpAndSettle();
    expect(tester.widget<CallView>(find.byType(CallView)).compact, false);
    await tester.tap(find.byTooltip('Minimize call'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingCallView), findsOneWidget);

    expect(configurations.last.arguments, {'call': 'dm/call', 'video': true});
    await _nativeEvent(tester, 'mode', {'call': 'dm/call', 'pip': true});
    tester.view.physicalSize = const Size(256, 144);
    await tester.pumpAndSettle();
    expect(find.byType(CallView), findsNothing,
        reason: 'PiP contains video, not controls or chats');
    expect(find.text('Settings'), findsNothing);
    expect(tester.takeException(), isNull,
        reason: 'hidden routes must not relayout into PiP dimensions');
    tester.view.physicalSize = const Size(400, 800);
    await _nativeEvent(tester, 'mode', {'call': 'dm/call', 'pip': false});
    await tester.pumpAndSettle();
    expect(find.byType(FloatingCallView), findsOneWidget);
    expect(bridge.countOf(BridgeMethod.callEnd), 0);
    expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 1);
    await _nativeEvent(tester, 'closed', {'call': 'dm/old-call'});
    expect(bridge.countOf(BridgeMethod.callEnd), 0,
        reason: 'stale PiP close is fenced');
    await _nativeEvent(tester, 'closed', {'call': 'dm/call'});
    await tester.pumpAndSettle();
    expect(bridge.countOf(BridgeMethod.callEnd), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    owner.dispose();
    router.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

Future<void> _nativeEvent(
    WidgetTester tester, String method, Map<String, Object> args) async {
  final reply = Completer<ByteData?>();
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      AndroidCallPresentation.channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      reply.complete);
  await reply.future;
}
