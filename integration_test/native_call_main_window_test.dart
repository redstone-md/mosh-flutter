import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mosh/src/features/voice_call/call_video_textures.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';

import 'support/native_call_scenario.dart';

/// The call in the main window (ADR 0052): one process, video in two textures
/// Rust feeds. The mute toggle acts on a live microphone; a host without an
/// audio input, as CI's runners are, sets `MOSH_CALL_UI_NO_MICROPHONE` to
/// leave that step out.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'a native AV call shows its video in main-window textures and keeps '
      'its controls while video runs', (tester) async {
    final scenario = await NativeCallScenario.start();
    final bridge = scenario.bridge;
    final textures = CallVideoTextures();
    final microphone =
        !Platform.environment.containsKey('MOSH_CALL_UI_NO_MICROPHONE');
    final owner =
        NativeCallOwner(bridge, () async => microphone, textures: textures);
    addTearDown(owner.dispose);
    final ui = await scenario.open(tester, owner);

    await ui.tap(find.byTooltip('Start video call'));
    await ui.eventually(() async => textures.value.local != null);
    await tester.pump(); // The lane may have appeared after the last frame.
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
    await tester.pump();
    expect(find.byType(Texture), findsNWidgets(2));
    expect(await polled(false), isNull, reason: 'no pixels cross the bridge');

    // test-policy: skip MOSH-95 -- CI's Windows and macOS runners have no audio input for the mute step
    if (microphone) {
      await ui
          .eventually(() async => owner.session!.snapshot!.microphone == true);
      await ui.tap(find.byTooltip('Mute'));
      await ui.eventually(() async =>
          owner.session!.snapshot!.microphoneRequested == false &&
          owner.session!.snapshot!.microphone == false &&
          find.byTooltip('Unmute').evaluate().isNotEmpty);
    }
    expect(textures.value.remote, isNotNull);

    await ui.tap(find.byTooltip('Minimize call'));
    await ui.send('Messaging during native video');
    expect(find.byType(Texture), findsWidgets,
        reason: 'the mini view keeps showing the call');
    await ui.tap(find.byTooltip('Expand call'));

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
    debugPrint('native-call-ui: main-window textures; '
        '${microphone ? 'mute and ' : ''}camera off retained the '
        'receive-only call');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    // test-policy: timeout MOSH-93 -- a real call over Moss with two engines
  }, timeout: const Timeout(Duration(minutes: 4)));
}
