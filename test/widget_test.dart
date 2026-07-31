import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import 'package:mosh/main.dart';

void main() {
  // Limitation: this test runs under `flutter test`, which has no native
  // Rust cdylib loaded. RustLib.init() and appDiagnostics() cannot exercise
  // the real FFI path here, so we do NOT call main() (it would throw on
  // RustLib.init). Instead we pump MoshApp directly. S2-1 swapped the home
  // from the MoshHome diagnostics smoke screen to OnboardingScreen (via
  // go_router). Onboarding reads only inviteFlowProvider (sync, no Rust) and
  // ARB strings, so it renders under `flutter test` without a gateway
  // override. The old diagnostics smoke proof lives in the diagnostics
  // screen + integration_test/slice_one_test.dart (real cdylib), not here.
  testWidgets('MoshApp routes to onboarding as the home screen', (tester) async {
    // MoshApp is a ConsumerWidget (S3.5), so it must run inside a ProviderScope
    // or Riverpod throws on ref.watch. The localeProvider default derives from
    // the device locale; we do not override it here (smoke test only).
    await tester.pumpWidget(const ProviderScope(child: MoshApp()));

    // go_router resolves the initial location '/' to OnboardingScreen. Let
    // localization settle (ARB load is async), then assert the home screen's
    // title renders. No Rust path is touched on a non-interactive pump.
    await tester.pumpAndSettle();
    expect(find.text('Start a conversation'), findsOneWidget);

    // The home must surface the route-shell entry points (S2-1): the Join
    // tile (-> /join) and the Group tile (-> later-slice placeholder, kept
    // 1:1 with the React OnboardMenu). Diagnostics is an AppBar action
    // (cable_outlined -> /diagnostics), not a tile, so the four React tiles
    // are not repurposed.
    expect(find.text('Join with a link'), findsOneWidget);
    expect(find.text('New group'), findsOneWidget);
    expect(find.byIcon(Icons.cable_outlined), findsOneWidget);
  });
}
