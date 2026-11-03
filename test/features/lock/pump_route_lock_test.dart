import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/features/invite_paste/invite_paste_screen.dart';
import 'package:mosh/src/features/lock/android_app_access.dart';
import 'package:mosh/src/features/lock/app_lock_route_observer.dart';
import 'package:mosh/src/features/settings/settings_screen.dart';
import 'package:mosh/src/features/shared/mosh_dialog_route.dart';
import 'package:mosh/src/features/voice_call/call_devices_dialog.dart';
import 'package:mosh/src/features/voice_call/call_media_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'package:mosh/src/state/rail_layout_provider.dart';

import '../../support/pump_route.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import '../../support/settings.dart';

// Size exception: main only registers independent route-lifetime cases.
void main() {
  testWidgets(
      'routed lock removes protected popups and keeps call devices usable',
      (tester) async {
    final fixture = _LockFixture(tester);
    await fixture.mount();
    final context = tester.element(find.byType(InvitePasteScreen));
    final protected = _protected(context, 'protected attachment');
    await tester.pumpAndSettle();
    expect(find.text('protected attachment'), findsOneWidget);
    CallViewCommand? selected;
    final devices =
        showCallDevices(context, _call).then((command) => selected = command);
    await tester.pumpAndSettle();

    await fixture.lock();
    expect(find.text('protected attachment'), findsNothing);
    await protected;
    expect(find.text('Call devices'), findsOneWidget);
    final lateProtected = _protected(context, 'late protected attachment');
    await tester.pumpAndSettle();
    expect(find.text('late protected attachment'), findsNothing);
    await lateProtected;

    await tester.tap(find.byType(MoshSelect<String?>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Loudspeaker'));
    await tester.pumpAndSettle();
    await devices;
    expect(selected?.action, CallViewAction.selectOutput);
    expect(selected?.deviceId, 'speaker');
    expect(selected?.callId, 'call');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a replacement routed app starts unlocked and still navigates',
      (tester) async {
    final fixture = _LockFixture(tester);
    await fixture.mount();
    await fixture.lock();
    final router = await pumpRoute(tester, AppRoutes.join, overrides: [
      gatewayProvider.overrideWithValue(fixture.gateway),
      bridgeFacadeProvider.overrideWithValue(fixture.bridge),
      ...settingsAudioOverrides(),
    ]);
    final context = tester.element(find.byType(InvitePasteScreen));
    final popup = _protected(context, 'new protected attachment');
    await tester.pumpAndSettle();
    expect(find.text('new protected attachment'), findsOneWidget);
    Navigator.of(context, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    await popup;
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('an explicit container retains unsaved layout across remounts',
      (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gateway = ScriptableGateway();
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(
          ScriptableBridge(conversations: gateway.conversations)),
      railLayoutStoreProvider.overrideWithValue(RailLayoutStore(null)),
    ]);
    addTearDown(container.dispose);
    await pumpRoute(tester, AppRoutes.sessions, container: container);
    final layout = container.read(railLayoutProvider.notifier);
    layout.preview(const RailLayout(collapsed: true));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand chat list'), findsOneWidget);

    await pumpRoute(tester, AppRoutes.sessions, container: container);
    expect(container.read(railLayoutProvider.notifier), same(layout));
    expect(find.byTooltip('Expand chat list'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

Future<void> _protected(BuildContext context, String label) =>
    showMoshDialog<void>(
        context: context, builder: (_) => AlertDialog(content: Text(label)));

class _LockFixture {
  _LockFixture(this.tester);

  final WidgetTester tester;
  final gateway = ScriptableGateway();
  late final bridge = ScriptableBridge(conversations: gateway.conversations);
  late final media = NativeCallOwner(bridge, () async => true);
  final access = AndroidAppAccess();
  var _revision = 0;
  var _allowed = true;

  Future<void> mount() async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidAppAccess.channel, (call) async {
      if (call.method == 'authenticateChats') return 'canceled';
      return {
        'version': 1,
        'delaySeconds': 60,
        'bootCount': 5,
        'deadlineElapsedMs': null,
        'state': _allowed ? 'interactive' : 'locked',
        'elapsedRealtimeMs': 1000,
        'allowed': _allowed,
        'revision': ++_revision,
        'shieldGeneration': 1,
        'deviceInteractive': true,
      };
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      access.dispose();
      media.dispose();
      messenger.setMockMethodCallHandler(AndroidAppAccess.channel, null);
      appLockRouteObserver.setLocked(false);
    });
    await access.initialize();
    await pumpRoute(tester, AppRoutes.join, overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
      androidAppAccessProvider.overrideWithValue(access),
      nativeCallOwnerProvider.overrideWithValue(media),
    ]);
  }

  Future<void> lock() async {
    _allowed = false;
    await access.refresh();
    await tester.pumpAndSettle();
  }
}

const _call = CallViewState(
    sessionId: 'dm',
    callId: 'call',
    peer: 'Contact',
    phase: CallViewPhase.active,
    media: CallMediaView(
        camera: false,
        cameraRequested: false,
        cameraStarting: false,
        cameraFailed: false,
        remoteCamera: false,
        microphoneAvailable: true,
        reconnecting: false,
        inputs: [],
        outputs: [CallDeviceView('speaker', 'Loudspeaker')],
        cameras: []));
