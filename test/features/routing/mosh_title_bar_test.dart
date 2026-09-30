// The desktop titlebar: the Peer status button as keyboard and screen
// readers meet it, and the bar and its StatePill at narrow widths and large
// text sizes.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors, moshThemeData;
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/routing/mosh_title_bar.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/pump.dart';
import '../../support/scriptable_gateway.dart';
import 'shell_harness.dart';

/// Pumps the titlebar alone, [width] wide, with a DM with Alice open so the
/// bar carries its StatePill. The rest of the shell is left out: this file
/// pins the bar, not the panes below it.
Future<void> _pumpBar(WidgetTester tester, {double width = 1200}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final gw = ScriptableGateway()
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
  testWidgets('the Peer status button is read once, by its visible text',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpBar(tester);

    expect(find.bySemanticsLabel('Connection status'), findsOneWidget);
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
