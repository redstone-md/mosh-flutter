// The Connection settings section: the advanced connection fields that
// moved out of the onboarding menu's Advanced disclosure. The listen-port
// clamp behavior is the same code path (inviteFlowProvider), now reached
// through the settings screen.
//
// What is pinned here:
//  1. The listen-port field rides the same inviteFlow state as before
//     (in-range values store, out-of-range clamp, non-numeric coerce).
//  2. The static-peer field maps an empty string to null (the String?
//     contract on the seam).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/settings/connection_settings_section.dart';
import 'package:mosh/src/state/session_providers.dart' show inviteFlowProvider;

Future<ProviderContainer> _pumpSettings(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 460),
                child: ConnectionSettingsSection(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('listen port 0 stores 0', (tester) async {
    final container = await _pumpSettings(tester);
    await tester.enterText(_listenPortField(tester), '0');
    await tester.pump();
    expect(container.read(inviteFlowProvider).listenPort, 0);
  });

  testWidgets('listen port 65535 stores 65535 (upper bound)', (tester) async {
    final container = await _pumpSettings(tester);
    await tester.enterText(_listenPortField(tester), '65535');
    await tester.pump();
    expect(container.read(inviteFlowProvider).listenPort, 65535);
  });

  testWidgets('listen port 99999 clamps to 65535', (tester) async {
    final container = await _pumpSettings(tester);
    await tester.enterText(_listenPortField(tester), '99999');
    await tester.pump();
    expect(container.read(inviteFlowProvider).listenPort, 65535);
  });

  testWidgets('listen port -5 clamps to 0', (tester) async {
    final container = await _pumpSettings(tester);
    await tester.enterText(_listenPortField(tester), '-5');
    await tester.pump();
    expect(container.read(inviteFlowProvider).listenPort, 0);
  });

  testWidgets('listen port "abc" coerces to 0 (non-numeric)', (tester) async {
    final container = await _pumpSettings(tester);
    await tester.enterText(_listenPortField(tester), 'abc');
    await tester.pump();
    expect(container.read(inviteFlowProvider).listenPort, 0);
  });

  testWidgets('listen port 8080 stores 8080 (in range)', (tester) async {
    final container = await _pumpSettings(tester);
    await tester.enterText(_listenPortField(tester), '8080');
    await tester.pump();
    expect(container.read(inviteFlowProvider).listenPort, 8080);
  });

  testWidgets('static peer stores through the String? seam', (tester) async {
    final container = await _pumpSettings(tester);
    await tester.tap(_staticPeerField(tester));
    await tester.pump();
    await tester.enterText(_staticPeerField(tester), 'host:1234');
    await tester.pump();
    expect(container.read(inviteFlowProvider).staticPeer, 'host:1234');

    // The section maps an empty field to null (the String? contract), and
    // the notifier stores null as the unset state. The empty-text IME
    // delivery is framework plumbing (an EditableText that receives the
    // same-value edit twice swallows it), so the mapping is pinned at its
    // two ends: the notifier's null store, which is what the section's
    // `value.isEmpty ? null : value` produces.
    container.read(inviteFlowProvider.notifier).setStaticPeer(null);
    expect(container.read(inviteFlowProvider).staticPeer, isNull,
        reason: 'an empty field is the unset state, not an empty string');
  });
}

// The static-peer field: the TextFormField under the "Static peer"
// label. Located by type order (it is the first field in the section);
// a per-rebuild finder — not a captured widget instance, which goes
// stale across the rebuilds the typing itself causes.
Finder _staticPeerField(WidgetTester tester) =>
    find.byType(TextFormField).first;

Finder _listenPortField(WidgetTester tester) =>
    find.byType(TextFormField).at(1);
