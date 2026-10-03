import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/features/settings/profile_settings_section.dart';
import 'package:mosh/src/state/session_providers.dart';

import '../../support/first_run.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('profile read failure retries without replacing the saved name',
      (tester) async {
    final store = MemoryFirstRunStore(
        const FirstRunProfile(displayName: 'Saved name', completed: true))
      ..readError = const FormatException('corrupt');
    final container = ProviderContainer(overrides: [
      firstRunStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    await pumpScreen(
        tester,
        const Scaffold(
            body: SingleChildScrollView(child: ProfileSettingsSection())),
        container: container);
    expect(find.textContaining('Could not read your setup'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    store.readError = null;
    await tapSetup(tester, 'Retry');
    expect(find.widgetWithText(TextFormField, 'Saved name'), findsOneWidget);
    expect(store.profile!.completed, isTrue);
  });

  testWidgets('saved profile name can be edited without reopening setup',
      (tester) async {
    final store = MemoryFirstRunStore(
        const FirstRunProfile(displayName: 'Old name', completed: true));
    final container = ProviderContainer(overrides: [
      firstRunStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    await pumpScreen(
        tester,
        const Scaffold(
            body: SingleChildScrollView(child: ProfileSettingsSection())),
        container: container);
    expect(find.widgetWithText(TextFormField, 'Old name'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'New name');
    await tapSetup(tester, 'Save name');
    expect(store.profile!.displayName, 'New name');
    expect(store.profile!.completed, isTrue);
    expect(container.read(inviteFlowProvider).displayName, 'New name');
    expect(find.text('Name saved.'), findsOneWidget);
  });
}
