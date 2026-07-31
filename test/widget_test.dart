import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/main.dart';

void main() {
  // Limitation: this test runs under `flutter test`, which has no native
  // Rust cdylib loaded. RustLib.init() and appDiagnostics() cannot exercise
  // the real FFI path here, so we do NOT call main() (it would throw on
  // RustLib.init). Instead we pump MoshApp directly. MoshHome wraps the
  // diagnostics call so an uninitialized bridge surfaces as the
  // FutureBuilder's error branch (red "diagnostics error:" Text) rather than
  // crashing. We assert the AppBar renders and the graceful error Text is
  // shown. The full bridge end-to-end proof is `flutter build windows
  // --debug`, not this unit test.
  testWidgets('MoshApp renders AppBar and handles uninitialized bridge gracefully', (tester) async {
    await tester.pumpWidget(const MoshApp());

    expect(find.text('Mosh'), findsOneWidget); // AppBar title renders

    // Resolve the FutureBuilder. Without the native runtime the diagnostics
    // future rejects; the graceful error Text must render (no crash).
    await tester.pumpAndSettle();
    expect(find.textContaining('diagnostics error:'), findsOneWidget);
  });
}
