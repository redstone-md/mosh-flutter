// The desktop titlebar: the Peer status button as keyboard and screen
// readers meet it, and the bar and its StatePill at narrow widths and large
// text sizes.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors, moshThemeData;
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/features/conversation/active_peer_status_drawer.dart';
import 'package:mosh/src/routing/mosh_title_bar.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/pump.dart';
import '../../support/scriptable_gateway.dart';
import '../../support/scriptable_bridge.dart';
import 'shell_harness.dart';

/// Pumps the titlebar alone, [width] wide, with a DM with Alice open so the
/// bar carries its StatePill. The rest of the shell is left out: this file
/// pins the bar, not the panes below it.
Future<void> _pumpBar(WidgetTester tester,
    {double width = 1200,
    ScriptableGateway? gateway,
    bool settle = true}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final gw = (gateway ?? ScriptableGateway())
    ..seedSessions([shellSession(sessionId: 'alice-1', peer: 'Alice')]);
  await pumpScreen(
    tester,
    Theme(
      data: moshThemeData,
      child: Scaffold(
        body: Column(
          children: [MoshTitleBar(onOpenPeerStatus: () {})],
        ),
      ),
    ),
    overrides: [
      gatewayProvider.overrideWithValue(gw),
      activeConversationProvider
          .overrideWithValue(ActiveConversation.parse('dm:alice-1')),
    ],
    settle: settle,
  );
}

void _scaleText(WidgetTester tester, double factor, {Locale? locale}) {
  tester.platformDispatcher.textScaleFactorTestValue = factor;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  if (locale != null) {
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  }
}

Finder _inTitleBar(Finder matching) =>
    find.descendant(of: find.byType(MoshTitleBar), matching: matching);

void main() {
  testWidgets('pending selected snapshot reports unknown, then its real state',
      (tester) async {
    final gateway = ScriptableGateway()..hold(GatewayMethod.poll);
    await _pumpBar(tester, gateway: gateway, settle: false);
    await tester.pump();
    expect(find.text('unknown'), findsOneWidget);
    gateway.release(GatewayMethod.poll);
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('diagnostic refresh stays disabled during its snapshot request',
      (tester) async {
    final gateway = ScriptableGateway()
      ..seedSessions([shellSession(sessionId: 'alice-1', peer: 'Alice')]);
    await pumpScreen(
        tester,
        Scaffold(
            body: Column(children: [
          MoshTitleBar(onOpenPeerStatus: () {}),
          Expanded(child: ActivePeerStatusDrawer(onClose: () {})),
        ])),
        overrides: [
          gatewayProvider.overrideWithValue(gateway),
          bridgeFacadeProvider.overrideWithValue(
              ScriptableBridge(conversations: gateway.conversations)),
          activeConversationProvider
              .overrideWithValue(ActiveConversation.parse('dm:alice-1')),
        ]);
    gateway.hold(GatewayMethod.poll);
    await tester.tap(find.byTooltip('Refresh status'));
    await tester.pump();
    await tester.pump();
    final button = find.ancestor(
        of: find.byTooltip('Refresh status'),
        matching: find.byType(IconButton));
    expect(tester.widget<IconButton>(button).onPressed, isNull);
    gateway.release(GatewayMethod.poll);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
  });

  testWidgets('narrow titlebar keeps actions and removes technical subtitle',
      (tester) async {
    await _pumpBar(tester, width: 320);
    expect(find.text('OpenMLS over Moss'), findsNothing);
    expect(find.text('MOSH'), findsNothing);
    expect(find.byTooltip('Connection status'), findsOneWidget);
    expect(find.byTooltip('Collapse chat list'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Peer status button is read once, by its visible text',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpBar(tester);

    expect(find.semantics.byLabel('Connection status'), findsOne);
    handle.dispose();
  });

  testWidgets('Tab onto the Peer status button draws the focus ring',
      (tester) async {
    await _pumpBar(tester);
    final ring = _inTitleBar(find.byType(FocusRing));
    expect(ring, findsOneWidget);
    bool ringShown() {
      final box = tester.widget<DecoratedBox>(
          find.descendant(of: ring, matching: find.byType(DecoratedBox)).first);
      final border = (box.decoration as BoxDecoration).border as Border?;
      return border?.top.color == MoshColors.focusRing;
    }

    expect(ringShown(), isFalse);
    for (var i = 0; i < 30 && !ringShown(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(ringShown(), isTrue);
  });

  testWidgets('581px wide, Russian, text at 200%: the bar does not overflow',
      (tester) async {
    _scaleText(tester, 2.0, locale: const Locale('ru'));
    await _pumpBar(tester, width: 581);

    expect(tester.takeException(), isNull);
    // The Peer status entry and the pill both stay reachable.
    expect(_inTitleBar(find.byTooltip('Статус подключения')), findsOneWidget);
    expect(_inTitleBar(find.byType(StatePill)), findsOneWidget);
  });

  testWidgets('StatePill grows with the text instead of clipping its label',
      (tester) async {
    _scaleText(tester, 2.0);
    await pumpScreen(
      tester,
      const Scaffold(
        body: Center(child: StatePill(state: 'ready', label: 'Connected')),
      ),
    );

    final label = tester.renderObject<RenderParagraph>(find.text('Connected'));
    expect(label.size.height,
        greaterThanOrEqualTo(label.getMinIntrinsicHeight(double.infinity)));
  });
}
