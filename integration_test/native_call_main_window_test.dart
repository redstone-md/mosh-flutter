import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mosh/src/features/voice_call/call_video_textures.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';

import 'support/native_call_scenario.dart';

/// The call in the main window (ADR 0052): one process, video in two textures
/// Rust feeds. It needs an audio input, as the mute toggle acts on a live
/// microphone.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'a native AV call shows its video in main-window textures and keeps '
      'its controls while video runs', (tester) async {
    final scenario = await NativeCallScenario.start();
    final bridge = scenario.bridge;
    final textures = CallVideoTextures();
    final owner = NativeCallOwner(bridge, () async => true, textures: textures);
    addTearDown(owner.dispose);
    final ui = await scenario.open(tester, owner);

    await ui.tap(find.byTooltip('Start video call'));
    await ui.eventually(() async => textures.value.local != null);
    expect(find.byType(Texture), findsOneWidget);
    final id = owner.session!.callId;
    Future<Object?> polled(bool local) => bridge.nativeCallFrame(
        sessionId: scenario.session,
        callId: id,
        local: local,
        after: BigInt.zero);
    expect(await polled(true), isNull, reason: 'no pixels cross the bridge');

    await scenario.answer(ui, id);
    await ui.eventually(() async =>
        textures.value.remote != null &&
        owner.session?.snapshot?.ready == true);
    expect(find.byType(Texture), findsNWidgets(2));
    expect(await polled(false), isNull, reason: 'no pixels cross the bridge');

    await ui
        .eventually(() async => owner.session!.snapshot!.microphone == true);
    await ui.tap(find.byTooltip('Mute'));
    await ui.eventually(() async =>
        owner.session!.snapshot!.microphoneRequested == false &&
        find.byTooltip('Unmute').evaluate().isNotEmpty);
    expect(textures.value.remote, isNotNull);

    await ui.tap(find.byTooltip('Minimize call'));
    await ui.send('Messaging during native video');
    expect(find.byType(Texture), findsWidgets,
        reason: 'the mini view keeps showing the call');
    await ui.tap(find.byTooltip('Show call window'));

    await ui.tap(find.byTooltip('Turn camera off'));
    await ui.eventually(() async =>
        owner.session!.snapshot!.cameraRequested == false &&
        textures.value.local == null);
    // test-policy: wait MOSH-93 -- real media must keep flowing for a while after the camera goes off; no event marks that
    Future<void> flowing() => Future<void>.delayed(const Duration(seconds: 2));
    await tester.runAsync(flowing);
    await tester.pump();
    expect(textures.value.remote, isNotNull);
    expect(owner.session!.snapshot!.ready, true);

    await ui.tap(find.byTooltip('Hang up'));
    await ui.eventually(scenario.ended);
    debugPrint('native-call-ui: main-window textures; mute and camera off '
        'retained the receive-only call');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    // test-policy: timeout MOSH-93 -- a real call over Moss with two engines, as native_call_test.dart
  }, timeout: const Timeout(Duration(minutes: 4)));
}
