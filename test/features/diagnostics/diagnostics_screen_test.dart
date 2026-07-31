// S4.8: widget test for the Diagnostics screen. Pumps it in a ProviderScope
// (with FakeGateway via the gateway seam) + a localized MaterialApp and
// asserts: app diagnostics show the canned appName "Mosh", and the native
// runtime section renders REAL field values from FakeGateway (the five
// NativeRuntimeStatus sub-structs are non-opaque across flutter_rust_bridge,
// so the card reads the fake's fields instead of an `<opaque>` placeholder).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_screen.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/state/gateway_provider.dart';

void main() {
  testWidgets('shows canned appName and real native runtime fields',
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

    // Native runtime now flows through the gateway seam (FakeGateway), so the
    // card renders the fake's real field values rather than an `<opaque>` row.
    // Moss runtime: libraryName "moss.dll" is unique to the native card
    // (AppDiagnostics only carries mossLinkMode "dynamic").
    expect(find.text('moss.dll'), findsOneWidget);
    // Secure storage: backend "os-keychain" is unique to the native card.
    expect(find.text('os-keychain'), findsOneWidget);
    // Persistence: backend "redb+aes-256-gcm+os-keychain" is unique.
    expect(find.text('redb+aes-256-gcm+os-keychain'), findsOneWidget);
    // OpenMLS smoke + roundtrip succeeded: the ok rows carry the provider id
    // and the ciphersuite inside the rendered snapshot string (two rows, one
    // per OpenMLS test).
    expect(find.textContaining('openmls_rust_crypto'), findsNWidgets(2));
    expect(
      find.textContaining(
          'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519'),
      findsNWidgets(2),
    );
    // Moss linkMode "dynamic" appears on both cards (app + native), so it must
    // be present at least once on the native runtime card.
    expect(find.text('dynamic'), findsNWidgets(2));
    // The pre-regen `<opaque>` placeholder and the unavailable row must be gone.
    expect(find.textContaining('<opaque>'), findsNothing);
    expect(find.text('unavailable'), findsNothing);
  });
}