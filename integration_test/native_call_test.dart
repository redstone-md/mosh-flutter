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
import 'package:mosh/src/features/voice_call/voice_call_binding.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';
import 'package:mosh/src/features/conversation/conversation_call_binding.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/private_dm.dart' as setup;
import 'package:mosh/src/rust/frb_generated.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/auto_poll_provider.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'package:window_manager/window_manager.dart';
import '../native_test/support/native_peer.dart';
import 'support/linked_dm_ui.dart';

Future<void> main(List<String> args) async {
  if (args.contains(callWindowProcessArgument) || isCallWindowProcess) {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    await launchProcessCallWindow();
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // One real Flutter app, one independent public-API installation, and a child
  // renderer. Only OS microphone consent and the camera driver are fixtures.
  testWidgets('native AV call keeps media through renderer loss and camera off',
      (tester) async {
    await windowManager.ensureInitialized();
    final data = Platform.environment['MOSH_CALL_UI_TEST_DATA_DIR'];
    if (data == null) {
      throw StateError('Use node scripts/moss-test.mjs --native-call-ui');
    }
    await RustLib.init();
    addTearDown(RustLib.dispose);
    await setup.setAppDataDir(path: data);
    await setup.setHistoryDek(dek: List.filled(32, 63));
    MediaKit.ensureInitialized();
    final peer = await NativePeer.start(api: true);
    addTearDown(peer.close);
    final invite = await peer.ask({'action': 'dm_invite'});
    final bridge = BridgeFacade();
    final local = await bridge.acceptInvite(
        request: AcceptInviteRequest(
            displayName: 'Local video caller',
            inviteUri: invite['invite_uri'] as String,
            listenPort: 0));
    final session = local.sessionId;
    final owner = NativeCallOwner(bridge, () async => false);
    addTearDown(owner.dispose);
    var previews = 0, remote = 0, opens = 0;
    final frames = owner.frames.listen((frame) {
      if (frame.local) {
        previews++;
      } else {
        remote++;
      }
    });
    addTearDown(frames.cancel);
    Process? child;
    final container = ProviderContainer(overrides: [
      nativeCallOwnerProvider.overrideWithValue(owner),
      conversationCallBindingProvider.overrideWithValue(voiceCallBinding),
      callWindowFactoryProvider.overrideWithValue((commands) async {
        opens++;
        return ProcessCallWindow.open(commands, startProcess: () async {
          child = await Process.start(
              Platform.resolvedExecutable, [callWindowProcessArgument],
              environment: {'MOSH_CALL_WINDOW': '1'});
          return child!;
        });
      }),
      autoPollIntervalProvider.overrideWithValue(kAutoPollInterval),
      firstRunEnabledProvider.overrideWithValue(false),
    ]);
    addTearDown(container.dispose);
    container.read(firstRunShownProvider.notifier).mark();
    appRouter.go(AppRoutes.dmFor(session));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MoshApp()));
    final ui = LinkedDmUi(tester, session);
    await ui.eventually(() async =>
        (await setup.pollSession(sessionId: session)).state ==
        DmSessionState.connected);
    await ui.tap(find.byTooltip('Start video call'));
    await ui.eventually(() async => previews > 5);
    final id = owner.session!.callId;
    expect(owner.session!.snapshot!.camera, true);
    expect(owner.session!.snapshot!.microphone, false);
    expect(
        await bridge.nativeCallFrame(
            sessionId: session, callId: id, local: false, after: BigInt.zero),
        isNull);
    await ui.eventually(() async {
      final view = await peer.ask({'action': 'dm_list'});
      return (view['sessions'] as List)
          .any((s) => s['pending_call']?['call_id'] == id);
    });
    await peer
        .ask({'action': 'call_accept', 'argument': session, 'call_id': id});
    await ui.eventually(() async =>
        (await setup.pollSession(sessionId: session)).activeCall?.callId == id);
    await peer.ask({
      'action': 'call_native_prepare',
      'argument': session,
      'call_id': id,
      'camera': true
    });
    await ui.eventually(
        () async => remote > 30 && owner.session?.snapshot?.ready == true);
    await ui.send('Messaging during native video');
    final before = remote;
    child!.kill();
    await child!.exitCode;
    await ui.eventually(() async => remote > before + 10);
    expect(owner.session!.snapshot!.ready, true);
    await ui.tap(find.byTooltip('Show call window'));
    await ui.eventually(() async => opens == 2);
    await ui.tap(find.byTooltip('Turn camera off'));
    await ui.eventually(
        () async => owner.session!.snapshot!.cameraRequested == false);
    final stopped = previews;
    final receiving = remote;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pump();
    expect(previews, stopped);
    expect(remote, greaterThan(receiving));
    expect(owner.session!.snapshot!.ready, true);
    await ui.tap(find.byTooltip('Hang up'));
    await ui.eventually(() async =>
        (await setup.pollSession(sessionId: session)).activeCall == null);
    debugPrint(
        'native-call-ui: previews=$previews remote=$remote renderer-opens=$opens; camera off retained receive-only call');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
