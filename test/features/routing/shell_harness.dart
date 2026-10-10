// The real app, pumped at a surface size, for the shell and titlebar tests.
//
// MoshApp owns the process-global appRouter, so the shell is exercised the
// way it ships: both branches, the titlebar, the drawer overlay. The two
// bridge providers are scripted doubles sharing one conversation state.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/main.dart';
import 'package:mosh/src/platform/desktop_window_controller.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import '../../support/settings.dart';

import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

/// A connected DM with [peer] on the other end.
SessionSnapshot shellSession(
        {required String sessionId, required String peer}) =>
    SessionSnapshot(
      inviteAvailable: false,
      sessionId: sessionId,
      meshId: 'testmesh',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: peer,
      state: DmSessionState.connected,
      transport: PeerTransport.direct,
      inviteUri: null,
      fingerprint: 'AABB',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

/// Pumps MoshApp at [physical] logical pixels (device pixel ratio 1), with
/// the router reset to the rail so a prior test's location does not leak.
Future<void> pumpShellApp(
  WidgetTester tester, {
  required ScriptableGateway gateway,
  required Size physical,
  DesktopWindowController? windowController,
}) async {
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  appRouter.go(AppRoutes.sessions);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gatewayProvider.overrideWithValue(gateway),
      ...settingsAudioOverrides(),
      bridgeFacadeProvider.overrideWithValue(
          ScriptableBridge(conversations: gateway.conversations)),
    ],
    child: MoshApp(windowController: windowController),
  ));
  await tester.pumpAndSettle();
}
