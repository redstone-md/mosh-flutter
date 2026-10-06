import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mosh/main.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/features/voice_call/call_window_app.dart';
import 'package:mosh/src/features/voice_call/process_call_window.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/private_dm.dart' as setup;
import 'package:mosh/src/rust/frb_generated.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/features/conversation/conversation_call_binding.dart';
import 'package:mosh/src/features/voice_call/voice_call_binding.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';
import 'package:mosh/src/state/auto_poll_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../native_test/support/native_peer.dart';
import 'support/call_audio_observer.dart';
import 'support/linked_dm_ui.dart';
import 'support/voice_call_scenario.dart';
import 'support/desktop_window_actions.dart';

Future<void> main(List<String> args) async {
  // Child engines run presentation directly, without starting a test suite.
  if (args.contains(callWindowProcessArgument) || isCallWindowProcess) {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    await launchProcessCallWindow();
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'two real desktop clients keep audio and controls across navigation',
      (tester) async {
    await windowManager.ensureInitialized();
    final storagePath = Platform.environment['MOSH_CALL_UI_TEST_DATA_DIR'];
    if (storagePath == null) {
      throw StateError('Use node scripts/moss-test.mjs --voice-ui');
    }
    final dir = Directory(storagePath);
    await RustLib.init();
    addTearDown(RustLib.dispose);
    await setup.setAppDataDir(path: dir.path);
    await setup.setHistoryDek(dek: List.filled(32, 61));
    MediaKit.ensureInitialized();
    final peer = await NativePeer.start(api: true);
    addTearDown(peer.close);
    final invite = await peer.ask({'action': 'dm_invite'});
    final local = await BridgeFacade().acceptInvite(
        request: AcceptInviteRequest(
            displayName: 'Local caller',
            inviteUri: invite['invite_uri'] as String,
            listenPort: 0));
    final audio = CallAudioObserver();
    appRouter.go(AppRoutes.dmFor(local.sessionId));
    final container = ProviderContainer(overrides: [
      conversationCallBindingProvider.overrideWithValue(voiceCallBinding),
      callWindowFactoryProvider.overrideWithValue(audio.openWindow),
      autoPollIntervalProvider.overrideWithValue(kAutoPollInterval),
      firstRunEnabledProvider.overrideWithValue(false),
      voiceCaptureFactoryProvider.overrideWithValue(audio.capture),
      voicePlaybackFactoryProvider.overrideWithValue(audio.playback),
      ringtonePlayerProvider.overrideWithValue(audio.ringtone),
    ]);
    addTearDown(container.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    container.read(firstRunShownProvider.notifier).mark();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MoshApp()));
    final flow = VoiceCallScenario(
        tester, peer, local.sessionId, invite['session_id'] as String, audio);
    await LinkedDmUi(tester, local.sessionId).eventually(() async =>
        (await setup.pollSession(sessionId: local.sessionId)).state ==
        DmSessionState.connected);
    debugPrint("voice-ui: outgoing decline and cancel");
    await flow.outgoingDeclineAndCancel();
    debugPrint("voice-ui: incoming and bidirectional media");
    final callId = await flow.incomingAndMedia();
    debugPrint("voice-ui: navigation and messaging");
    await flow.navigationAndMessaging();
    debugPrint("voice-ui: remote end and repeat");
    await flow.remoteEndAndRepeat(callId);
    debugPrint("voice-ui: native window actions");
    await DesktopCallWindowScenario(flow).run();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
