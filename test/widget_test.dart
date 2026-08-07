import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/main.dart';
import 'package:mosh/src/features/onboarding/new_session_panel.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/routing/mosh_shell.dart';

void main() {
  // Limitation: this test runs under `flutter test`, which has no native
  // Rust cdylib loaded. RustLib.init() and appDiagnostics() cannot exercise
  // the real FFI path here, so we do NOT call main() (it would throw on
  // RustLib.init). Instead we pump MoshApp directly. The app opens directly
  // inside the StatefulShellRoute (mosh_shell.dart -- the React
  // PrivateDmScreen parity: rail + chat-pane two-pane shell), with
  // initialLocation = AppRoutes.sessions (branch A, the rail). Branch B
  // (/chat, ChatPaneWelcome with the inline NewSessionPanel) is preloaded so
  // the desktop right pane renders on startup. The shell + welcome read
  // only sync providers + ARB strings, so they render under `flutter test`
  // without a gateway override. The old diagnostics smoke proof lives in
  // the diagnostics screen + integration_test/slice_one_test.dart (real
  // cdylib), not here.
  testWidgets('MoshApp opens directly into the shell (rail + welcome)',
      (tester) async {
    // MoshApp is a ConsumerWidget (S3.5), so it must run inside a ProviderScope
    // or Riverpod throws on ref.watch. The localeProvider default derives from
    // the device locale; we do not override it here (smoke test only).
    await tester.pumpWidget(const ProviderScope(child: MoshApp()));

    // go_router resolves the initial location '/sessions' to the shell
    // (MoshShell): branch A (SessionsScreen, the rail) on mobile / left pane
    // on desktop, branch B (ChatPaneWelcome with the inline NewSessionPanel)
    // preloaded as the desktop right pane. Let localization settle (ARB load
    // is async), then assert the shell mounts and the inline welcome renders.
    // No Rust path is touched on a non-interactive pump.
    await tester.pumpAndSettle();
    expect(find.byType(MoshShell), findsOneWidget);
    expect(find.byType(SessionsScreen), findsOneWidget);
    // The preloaded chat branch renders the inline welcome (NewSessionPanel
    // -> OnboardMenu with the onboard title). On mobile the chat branch is
    // offstage, so the assertions use skipOffstage default semantics; the
    // shell test suite covers the desktop/mobile layout split in detail.
    expect(find.byType(NewSessionPanel), findsOneWidget);
    expect(find.text('Start a conversation'), findsOneWidget);

    // The inline welcome's OnboardMenu also surfaces the Join / New group
    // tiles (React NewSessionPanel parity -- they live in the welcome, not
    // the onboarding route), so they render here too.
    expect(find.text('Join with a link'), findsOneWidget);
    expect(find.text('New group'), findsOneWidget);
  });
}
