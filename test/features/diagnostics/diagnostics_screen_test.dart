// S4.8: widget test for the Diagnostics screen. Pumps it in a ProviderScope
// (with FakeGateway via the gateway seam) + a localized MaterialApp and
// asserts: app diagnostics show the canned appName "Mosh", and the native
// runtime section degrades gracefully (no crash) when RustLib is not
// initialized in the test env (the frb nativeRuntimeStatus() call fails).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_screen.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/state/gateway_provider.dart';

void main() {
  testWidgets('shows canned appName and degrades native runtime gracefully',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [gatewayProvider.overrideWithValue(FakeGateway())],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DiagnosticsScreen(),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // App diagnostics come from FakeGateway.appDiagnostics() -> "Mosh".
    expect(find.text('Mosh'), findsOneWidget);
    // Native runtime: RustLib is not initialized in tests, so the frb call
    // fails; the screen must show the unavailable/error row, not crash.
    expect(find.text('unavailable'), findsOneWidget);
  });
}
