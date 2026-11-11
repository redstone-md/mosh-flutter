import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mosh/main.dart';
import 'package:mosh/src/features/conversation/conversation_call_binding.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/features/voice_call/voice_call_binding.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/private_dm.dart' as setup;
import 'package:mosh/src/rust/frb_generated.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/auto_poll_provider.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../native_test/support/native_peer.dart';
import 'linked_dm_ui.dart';

/// One real Flutter app in a DM with an independent public-API installation
/// over real Moss. Only OS microphone consent and the camera driver are
/// fixtures.
final class NativeCallScenario {
  NativeCallScenario._(this.bridge, this.peer, this.session);

  final BridgeFacade bridge;
  final NativePeer peer;
  final String session;

  static Future<NativeCallScenario> start() async {
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
    return NativeCallScenario._(bridge, peer, local.sessionId);
  }

  /// Opens the app on the DM, connected, with `owner` as its call media.
  Future<LinkedDmUi> open(WidgetTester tester, NativeCallOwner owner,
      {List<Override> overrides = const []}) async {
    final container = ProviderContainer(overrides: [
      nativeCallOwnerProvider.overrideWithValue(owner),
      conversationCallBindingProvider.overrideWithValue(voiceCallBinding),
      autoPollIntervalProvider.overrideWithValue(kAutoPollInterval),
      firstRunEnabledProvider.overrideWithValue(false),
      ...overrides,
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
    return ui;
  }

  /// The peer answers `call` and turns its camera on.
  Future<void> answer(LinkedDmUi ui, String call) async {
    await ui.eventually(() async {
      final view = await peer.ask({'action': 'dm_list'});
      return (view['sessions'] as List)
          .any((s) => s['pending_call']?['call_id'] == call);
    });
    await peer
        .ask({'action': 'call_accept', 'argument': session, 'call_id': call});
    await ui.eventually(() async =>
        (await setup.pollSession(sessionId: session)).activeCall?.callId ==
        call);
    await peer.ask({
      'action': 'call_native_prepare',
      'argument': session,
      'call_id': call,
      'camera': true
    });
  }

  Future<bool> ended() async =>
      (await setup.pollSession(sessionId: session)).activeCall == null;
}
