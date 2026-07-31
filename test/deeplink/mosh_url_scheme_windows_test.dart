// S2-2: guard test for the Windows `mosh://` URL-scheme registration.
//
// The registration function is a Windows-only side effect that writes to the
// real Windows registry (HKCU\Software\Classes\mosh). It must NOT be invoked
// from the test harness: `flutter test` runs on the host, and on a Windows
// host that would mutate real registry state. So this test does NOT call
// `registerMoshUrlScheme()`; it asserts only the static contract the slice
// requires:
//   - the public symbol `registerMoshUrlScheme` is exported (compiles + is a
//     top-level function), and
//   - the single-scheme constant `kMoshUrlScheme` equals `'mosh'` (ADR 0015:
//     one scheme everywhere, no per-fork `mosh-flutter://` variant).
//
// The Platform.isWindows gate + try/catch inside the function itself keeps
// the host from being affected even if it is ever called, but we keep the
// harness conservative and never call it here.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/deeplink/mosh_url_scheme_windows.dart';

void main() {
  test('registerMoshUrlScheme is exported as a top-level function', () {
    // A static reference proves the symbol exists and is callable without
    // invoking the registry side effect.
    expect(registerMoshUrlScheme, isA<void Function()>());
  });

  test('kMoshUrlScheme is the single mosh:// scheme (ADR 0015)', () {
    expect(kMoshUrlScheme, 'mosh');
  });
}
