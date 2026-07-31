// S4.4: widget test for the slice-one onboarding screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/onboarding_screen.dart';
import 'package:mosh/src/state/session_providers.dart';

void main() {
  testWidgets('onboarding renders title, binds name to inviteFlow, chat tile taps', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Title resolves from the ARB (en) -> "Start a conversation".
    expect(find.text('Start a conversation'), findsOneWidget);
    expect(find.text('New private chat'), findsOneWidget);

    // Entering text must flow into inviteFlowProvider.displayName.
    await tester.enterText(find.byType(TextField), 'juno-laptop');
    await tester.pump();
    expect(container.read(inviteFlowProvider).displayName, 'juno-laptop');

    // Tapping the Chat tile runs inviteFlowProvider.create() (FakeGateway); the
    // resulting invite URI surfaces as a SnackBar. No crash = tile is tappable.
    await tester.tap(find.text('New private chat'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
