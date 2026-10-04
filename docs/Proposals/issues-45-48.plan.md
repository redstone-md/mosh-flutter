# Composer and interface language

Approved scope: GitHub issues #48 and #45. Message deletion, chat renaming and
video calls remain separate requests.

## Work

1. Reproduce focus loss and consecutive keyboard sends in all conversation kinds.
   Keep the composer editable, capture each submitted draft immediately and admit
   text sends in order. Preserve separate failed submissions and existing native
   message delivery states. Completion must not clear a newer draft or steal focus.
2. Add System, Russian and English to Profile settings using the existing selector.
   Persist only the explicit interface-language preference, independently of setup.
   Let Flutter resolve system locales and follow OS changes; English is the fallback.
3. Translate the existing macOS menu labels without replacing their Cocoa actions
   or shortcuts. OS-owned services and dialogs retain the OS's own localization.

## Risks and checks

- Exercise held sends, identical bodies, failures, retry, navigation/disposal and
  revoked input. Native admission stays ordered; delivery remains native-owned.
- Exercise saved language on restart, missing/invalid preferences, failed writes,
  live system-language changes and responsive settings.
- Run formatting, Flutter analysis and the full widget suite with coverage.
  Measure changed executable lines and branches against the repository gates.
- Native macOS menu behavior needs the macOS build lane or a physical Mac; the
  development host is Linux. Verify Dart channel payloads and native menu mappings.
- Keep dependencies, Rust bridge and existing persistence schemas unchanged.

Use one verified Conventional Commit per issue. Publication requires a separate
reviewable handoff; no GitHub mutations are part of this local implementation.
