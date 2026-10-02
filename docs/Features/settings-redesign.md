# Settings redesign

The [approved plan](../Proposals/settings-redesign.plan.md) is delivered on
`feat/settings-redesign`, one screen per local development-build review.
The settings frame, Sound and Devices are implemented. Connection, Privacy
and About retain their existing controls until their redesign stages.

## Navigation

- The rail gear pushes a root settings route above the chat shell. Closing
  settings restores the mounted conversation rather than recreating it.
  Direct route entry falls back to the chat list.
- At widths of at least 800px a 280px sidebar accompanies content capped at
  800px. The existing titlebar retains branding without a global network badge.
  Sound opens first; the last section survives closing settings during this
  application launch. Restarting the application resets that choice.
- Narrow windows and Android start with the section list. Selecting a section
  opens its detail view. The toolbar back button, system Back and Escape return
  to the list before closing settings. Every narrow entry starts at the list;
  only the wide sidebar restores the last section's content.
  The explicit Back to chats action closes settings directly.
- Shared Mosh colors, shapes, focus rings and Material controls supply the
  visual style. Longer hardware names truncate inside selectors; explanations
  wrap and the entire section scrolls for narrow windows or larger text.
  Selection popovers and action menus share 12px corners, a raised background
  and clipped contents so focus and hover fills stay within the rounded menu.

## Sound

- Microphone and speaker cards consume the existing Riverpod device providers
  and persisted `audio-devices.json` choices. Changing one preserves the other.
  Choices apply to subsequent recording or playback as before.
- Loading disables a selector. Enumeration failure offers retry and system
  default selection. A disconnected saved device remains visible as unavailable
  until the user chooses another; a failed save displays an error and keeps the
  persisted selection in the field.
- The existing ringtone player provides the speaker test. Stop, the 1.5-second
  timer and section disposal release the handle. Playback errors are visible
  and can be retried. No additional microphone test or video controls appear.

## Adaptive menus

The user approved trying this pattern after reviewing the rounded legacy
dropdowns. Microphone, speaker and adapter choices now use one controlled
`MoshSelect`. Desktop opens a Material `MenuAnchor` beneath the field with a
6px gap; Android, iOS and windows below 600px use a titled bottom sheet. The
chat action menu uses the same popover rows on all platforms.

Panels have 12px corners, 4px internal padding and 8px row corners. Rows and
choice buttons are at least 44px high before text scaling. The current choice
has a muted green background and checkmark; hover, focus, disabled and danger
states use the shared theme. Long names wrap in the choices while the closed
field stays compact. Scrollable menus and sheets keep larger lists bounded.

Material owns keyboard navigation, overlay positioning, dismissal and focus
return. Closing the sheet applies nothing; choosing System default still
applies the real nullable value. The field displays the persisted selection,
including after a failed save. Adapter selection stays local until Bind is
pressed. No dependency or native contract changes are required.

Interaction tests cover desktop placement/current-choice indication, keyboard
selection and Escape, mobile dismissal, nullable choices, unavailable devices,
long names at 320px, disabled chat actions and adapter application. Open Sound
menus were inspected at 1000×844 and 390×844 with the production theme.

Menu-trial verification: Flutter analysis and formatting are clean; the full
suite passes 1041 tests with five existing native-library skips. Changed
production executable line coverage is 172/173 (99.4%); changed branch coverage
is 44/44 (100%). The Android arm64 debug APK builds. Physical desktop/phone
review determines whether to keep this pattern or try the alternative.

The existing `mosh_theme.dart` exceeds the 400-line file limit because it holds
the palette and declarative theme configuration. New menu recipes live in
`mosh_menu_theme.dart`; handlers remain below 50 lines. Declarative widget trees
and test registration functions retain the nesting/length exception described
above; individual interaction test bodies remain small.

## Checks and limits

Route tests exercise preservation of shell state, chat scroll and draft,
section memory, wide/narrow navigation and both system Back and Escape.
Audio tests cover partial choices, disconnected devices, loading, enumeration
retry, persistence errors and sound
cleanup on stop, timeout and disposal.

Production-themed widget captures were inspected at 1440×900 and 390×844,
plus a 320×600 window with doubled text size. Local captures load Material icons
and the Linux fallback font; they are temporary inspection artifacts.
Native Windows/Android audio hardware and window behavior require the local
development build. Stage one leaves Rust APIs, dependencies and storage unchanged.
Devices changes pairing APIs and saved exchange context as approved below.

Declarative widget construction exceeds three levels of nesting in the frame
and cards; control flow remains shallow and the trees are split by concern.
Existing router and titlebar orchestration/build methods exceed the 50-line
function limit; this stage moves route ownership and adds the branding variant.

## Verification results

- `dart format lib test integration_test`: all 424 files formatted.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --branch-coverage`: 1017 passed, 5 skipped by existing
  native-library gates (four Windows DLL probes and one libmpv probe).
- Changed production executable lines: 274/275 (99.6%); changed branches:
  83/88 (94.3%). Counts intersect LCOV with added/modified Dart lines.
- `git diff --check`: clean.
- Phone review follow-up: narrow reopening always starts with the section list.
  Both audio/VPN dropdowns and the chat action menu use clipped 12px corners.
  Regression checks first reproduced the automatic Sound entry and unclipped
  dropdown, then passed after the fixes. Full suite: 1019 passed, 5 existing
  native-library skips; analysis and formatting are clean.

## Devices

The signed roster shows device names, short identifiers, the current installation
and actual removal progress. Two actions explain their roles before opening the
pairing steps. The trusted installation creates a five-minute, single-use v2 QR;
the new installation reads it and shows a confirmation code. The trusted
installation enters that code before approving access.

Android can scan with its camera using the bundled offline scanner. Image and
link import are available everywhere, including after camera denial or failure.
Existing removal confirmation and native authorization remain in use. See
[device linking](device-linking.md) for the protocol, upgrade behavior and tests.

Devices verification on 2026-10-02:

- Flutter analysis and formatting are clean; the full suite passes 1032 tests
  with the same five native-library skips. Responsive layout and camera plugin
  tests cover enlarged text, permission failure, repeated capture and lifecycle.
- The production-themed native UI probe passes with a separate real Moss process.
  The full Rust suite, build, formatting and clippy pass. Binding regeneration
  produces no drift. The Android arm64 debug APK builds with camera permission,
  an optional camera hardware requirement and the bundled scanner model.
- Changed Dart executable lines: 278/294 (94.6%); branches: 77/87 (88.5%).
  Changed Rust executable lines: 256/272 (94.1%). This stable Rust toolchain does
  not emit branch coverage. Generated bindings are excluded from these counts.
- Standards and specification review findings are resolved, including descriptor
  substitution and delayed approval after a newer signed removal. Native tests
  cover committed v1 recovery, first-scanner ownership, replay and revocation.
- Desktop and narrow captures were inspected at 1200×950 and 360×950. Physical
  Android camera scanning and native Windows behavior need the local dev build.

The next screen is Connection, after the user's Devices review.

## Changed files

- `lib/src/features/settings/`: `settings_screen.dart`,
  `settings_navigation.dart`, `settings_nav.dart`, `settings_content.dart`,
  `settings_card.dart`, `audio_device_picker.dart`, `voice_settings_section.dart`.
- `lib/src/features/sessions/`: `sessions_screen.dart`, `rail_item.dart`.
- `lib/src/routing/`: `app_router.dart`, `mosh_title_bar.dart`.
- `lib/l10n/`: `app_en.arb`, `app_ru.arb`.
- `test/features/settings/`: `settings_screen_test.dart`,
  `voice_settings_section_test.dart`; `test/support/settings.dart`.
- `docs/Architecture.md`, `docs/Proposals/settings-redesign.plan.md`,
  `docs/Features/settings-redesign.md`.

Devices also changes `lib/src/features/device_link/`, generated bridge files,
`mosh-core/src/device_link/`, `mosh-core/src/api/device_link.rs`, `pubspec.yaml`
and its lockfile. Device-link tests, the Android linked-DM scenario and pairing
documentation follow the new direction.

The menu trial adds `lib/src/app/mosh_select.dart`, `mosh_menu_item.dart` and
`mosh_menu_theme.dart`, and updates `mosh_theme.dart`, `audio_device_picker.dart`,
`bind_interface_field.dart` and `chat_header_menu.dart`. Interaction tests are
in `test/app/dropdown_menu_test.dart` and `chat_header_menu_test.dart`; existing
Sound, adapter and shell tests follow the shared controls.
