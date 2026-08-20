// OnboardMenu listen-port clamp -- React parity for
// NewSessionPanelMenu.tsx:85-90 (`<input type="number" min={0} max={65535}
// ... onChange={e => props.onListenPort(Number(e.target.value) || 0)} />`).
// The browser enforces the min/max range on the number input; Flutter has no
// native ranged numeric input, so `_onListenPortChanged` clamps the parsed
// value to 0..65535 before storing it in inviteFlow (the stored value is what
// reaches Rust as listen_port). The field text is NOT rewritten on clamp
// (a mid-typing rewrite is jarring); only the stored value is constrained.
//
// Pumps the bare OnboardMenu (lighter than the full appRouter screen) with a
// test gateway override so BindInterfaceField's async initState stays
// deterministic, expands the Advanced disclosure, and types into the
// listen-port field (the third TextField in the menu: name, staticPeer,
// listenPort). Asserts the clamped stored value on inviteFlowProvider.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/onboard_menu.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

void main() {
  // Pumps OnboardMenu with the test gateway so BindInterfaceField's
  // listInterfaces/getBindInterface resolve synchronously and the Advanced
  // disclosure can be expanded to reach the listen-port field.
  Future<ProviderContainer> pumpMenu(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(ScriptableGateway()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: const OnboardMenu(
                    onPickChat: noop,
                    onPickGroup: noop,
                    onPickJoin: noop,
                    onPickChannel: noop,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The Advanced disclosure sits below the fold in the default 800x600
    // viewport, so scroll it into view before tapping (matches how the
    // channel/group navigation tests reach off-screen tiles).
    await tester.scrollUntilVisible(
      find.text('Advanced connection settings'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    // Expand the Advanced disclosure so the listen-port field mounts.
    await tester.tap(find.text('Advanced connection settings'));
    await tester.pumpAndSettle();

    return container;
  }

  // The listen-port field is the last TextField in the menu (name, then
  // staticPeer, then listenPort). The controller is seeded from the provider
  // default (8765); clear it first so enterText replaces rather than
  // appends (clamping "87650" would still pass, but appending to "abc"
  // would mask the non-numeric coercion).
  Future<void> typeListenPort(WidgetTester tester, String text) async {
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    final listenPortField = fields.last;
    final finder = find.byWidget(listenPortField);
    // The listen-port field sits below the fold once the Advanced disclosure
    // expands; scroll its "Listen port" label into view so the field is
    // tappable (no off-screen hit-test warnings).
    await tester.scrollUntilVisible(
      find.text('Listen port'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(finder);
    await tester.pump();
    // The controller is seeded from the provider default (8765); clear it
    // before typing so enterText replaces rather than appends (clamping
    // "87650" would pass, but appending to "abc" would mask coercion).
    listenPortField.controller!.clear();
    await tester.enterText(finder, text);
    await tester.pump();
  }

  testWidgets('listen port 0 stores 0', (tester) async {
    final container = await pumpMenu(tester);
    await typeListenPort(tester, '0');
    expect(container.read(inviteFlowProvider).listenPort, 0);
  });

  testWidgets('listen port 65535 stores 65535 (upper bound)', (tester) async {
    final container = await pumpMenu(tester);
    await typeListenPort(tester, '65535');
    expect(container.read(inviteFlowProvider).listenPort, 65535);
  });

  testWidgets('listen port 99999 clamps to 65535', (tester) async {
    final container = await pumpMenu(tester);
    await typeListenPort(tester, '99999');
    expect(container.read(inviteFlowProvider).listenPort, 65535);
  });

  testWidgets('listen port -5 clamps to 0', (tester) async {
    final container = await pumpMenu(tester);
    await typeListenPort(tester, '-5');
    expect(container.read(inviteFlowProvider).listenPort, 0);
  });

  testWidgets('listen port "abc" coerces to 0 (non-numeric)', (tester) async {
    final container = await pumpMenu(tester);
    await typeListenPort(tester, 'abc');
    expect(container.read(inviteFlowProvider).listenPort, 0);
  });

  testWidgets('listen port 8080 stores 8080 (in range)', (tester) async {
    final container = await pumpMenu(tester);
    await typeListenPort(tester, '8080');
    expect(container.read(inviteFlowProvider).listenPort, 8080);
  });
}

void noop() {}
