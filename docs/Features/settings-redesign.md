# Settings redesign

The [approved plan](../Proposals/settings-redesign.plan.md) is delivered on
`feat/settings-redesign`, one screen per local development-build review.
The settings frame and all five sections are implemented: Sound, Devices,
Connection, Privacy and About.
Read receipts have moved to Privacy.

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

The user accepted this pattern after reviewing an isolated inline alternative.
Microphone, speaker and adapter choices now use one controlled
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
including after a failed save. Adapter selection stays local until the VPN
bypass switch is enabled. No dependency or native contract changes are required.

Interaction tests cover desktop placement/current-choice indication, keyboard
selection and Escape, mobile dismissal, nullable choices, unavailable devices,
long names at 320px, disabled chat actions and adapter application. Open Sound
menus were inspected at 1000×844 and 390×844 with the production theme.

Menu-trial verification: Flutter analysis and formatting are clean; the full
suite passes 1041 tests with five existing native-library skips. Changed
production executable line coverage is 172/173 (99.4%); changed branch coverage
is 44/44 (100%). The Android arm64 debug APK builds. Physical desktop/phone
review remains useful for platform-specific behavior.

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

## Connection

Connection contains only the collapsible VPN adapter controls. Automatic
discovery continues without a card or editable host/port fields. The existing
read-receipt switch now lives beside crash reporting in Privacy, with its
persistence, default-off state and mutual rule unchanged.

The VPN card loads its controls on first expansion and retains local state
when collapsed. It reuses the Sound card's material, icon badge and
adaptive selector. The adapter form uses the existing interface inventory,
physical-adapter filter and consent write. Choosing a name remains local until
the VPN bypass switch is enabled. Disabling the switch clears the stored
override, including when the saved adapter has disappeared. Explicit On/Off
text accompanies the switch, derived from the saved adapter rather than an
assumption about a running node. Loading and read failures show their own state
and disable changes; pending writes disable repeat taps. A failed write leaves
the previous switch value intact. A refresh icon beside the selector retains
its tooltip and 44px target. Selecting another adapter requires disabling the
existing override first, as before.

The LAN IP and VPN bypass warning stays beside the controls. A saved adapter is
labelled as saved, rather than as a live connection. Windows invokes the scoped
relauncher after a successful write, even if the user has left the section.
Other platforms show instructions to fully close and reopen Mosh. Returning
relaunch callbacks release the busy state; a failed save or restart shows a
localized error. Read errors can be retried.

Per the user's screen review, Connection has no diagnostics/status card or
refresh-status action. Version information stays in About. Chat diagnostics
keep their existing providers and runtime details.

The VPN disclosure uses a stable PageStorage key. Its expansion boolean cannot
overwrite the section scroller's numeric offset. Restoring an open VPN
disclosure also mounts its controls. Each shared selector owns a separate
PageStorage bucket: the MenuAnchor popup's internal scroll view must not read
the enclosing disclosure's boolean as a numeric offset. Regression tests use
the real SettingsScreen with an explicit Windows theme to exercise the desktop
popup rather than the test environment's default Android sheet. They cover
opening, choosing, scrolling, leaving and returning alongside section scroll
restoration and narrow Back navigation.

New production files remain below 200 lines. Adapter presentation is split
into the switch, picker row, selector and refresh control; methods remain
below 50 lines.
Declarative widget nesting uses the existing settings exception.

Initial Connection verification on 2026-10-02:

- Formatting and Flutter analysis are clean. The full Flutter suite passes
  1050 tests with the same five native-library skips. The final focused
  settings, adapter, relaunch and read-receipt suite passes 48 tests.
- Changed production executable line coverage is 193/193 (100%); changed
  branch coverage is 50/51 (98%). Counts intersect added/modified lines
  with the final focused LCOV report.
- Production-themed captures were inspected at 1200×1100 and 390×1050.
  The layout test also covers 320px with doubled text. The Android arm64
  debug APK builds successfully.
- Windows process relaunch and actual VPN routing still require a local
  development build. This stage changes no native API, dependency or storage.

The next screen is Privacy, after the user's Connection review.

Connection review follow-up:

- Removed the diagnostics card, its refresh action, widget and unused
  translations at the user's request. Version information stays in About.
- Six regression checks cover the exact reopening crash, restored controls,
  disclosure state, scroll offset and narrow Back navigation.
  Full Flutter suite: 1051 passed, five existing native-library skips.
  Analysis and formatting are clean. Changed executable lines: 5/5;
  changed branches: 1/1, from full-suite LCOV against `e76d3ad`.
- Updated desktop and narrow captures were inspected. Android arm64 debug
  APK builds successfully.

Adapter-menu and button review follow-up:

- Removed the discovery card and its unused translations. Apply/Reset now
  use neutral outlined buttons; refreshing the adapter list uses an icon
  beside the selector. Native application and restart behavior are unchanged.
- Reproduced the exact bool-to-double cast when opening the desktop adapter
  menu. Isolating the shared selector's PageStorage fixes opening, selection,
  popup scrolling and subsequent section return.
- Formatting and analysis are clean; the full Flutter suite passes 1051 tests
  with five existing native-library skips. Changed executable lines: 55/56
  (98.2%); branches: 10/10 (100%), against `9abb99e`.
- Production-themed captures were inspected at 1200×800 and 390×844,
  including the desktop popup and Android sheet. The Android arm64 debug
  APK builds successfully. Windows relaunch and physical VPN routing still
  need the user's local development-build review.

VPN switch follow-up:

- Replaced Apply/Reset with the saved-state VPN bypass switch and explicit
  On/Off text. Loading and unknown states disable it; failed writes preserve
  the prior value. The existing successful-write relaunch remains in use.
- Widget checks cover both directions, saved state after section return,
  loading/read failure, duplicate taps, unavailable adapters and failed
  writes/relaunch. Full Flutter suite: 1053 passed, five existing native-library
  skips. Analysis and formatting are clean. Changed executable lines: 38/38;
  changed branches: 10/10, against `96282bb`.
- Both switch states were inspected in the production UI at 1200×800 and
  390×844. The Android arm64 debug APK builds successfully.
  Windows relaunch and physical VPN routing require local review;
  other platforms retain their existing manual-restart behavior.

VPN restart correction:

- The switch now reads `getVpnBypassConsent` instead of the process-local
  `getBindInterface`. The previous tests seeded live binding, which concealed
  the fresh-process reset. Four new widget checks reproduce both saved states
  and both toggle directions after the widget is fully recreated.
- Shared runtime startup now loads the same persisted consent before the
  Moss node can start. Existing name/index resolution handles renamed adapters;
  unavailable adapters fall back to default routing without clearing consent.
  Explicit process overrides retain priority, and saving settings does not
  change an already running node.
- A real-process regression failed before the fix with a saved adapter and
  an unbound new node. The native checks launch independent processes against
  the same private data directory and exercise enable/restart/disable/restart,
  renamed/unavailable adapters and explicit overrides using real Moss.
- No bridge signatures, settings schema or dependencies changed. Actual
  Windows process relaunch and routing through a physical VPN remain local
  development-build checks.
- Verification: Flutter analysis is clean; 1057 Flutter tests pass with five
  existing native-library skips. The full native suite passes 471 tests,
  with 18 ignored entries including the worker launched by the restart tests.
  After consolidating the two routing fallbacks, all 435 native unit tests and
  four restart checks pass again. Cargo build, formatting and Clippy are clean;
  the Android arm64 debug APK builds. Changed executable lines are covered:
  Dart 2/2 and Rust 20/20. No changed Dart branches are reported; Rust branch
  instrumentation is unavailable on the pinned stable toolchain.

Switch hover correction: the shared theme keeps enabled, selected thumbs in
`mossInk` on hover, focus and press. Material's default used `primaryContainer`,
which matches the green track in Mosh. No tests added or run for this small
color fix, as requested; formatting and Flutter analysis are checked.

Adapter refresh retains the last loaded controls while the request is pending,
so the VPN card does not collapse and reopen. The picker, refresh button and
switch are disabled until completion. Errors remain visible during retry and
clear on success; a failed read still marks the state unknown. This small UI
fix follows the same requested no-tests scope; format and analysis are checked.

## Privacy

Privacy presents crash reporting and read receipts as two opt-in cards using
the existing settings surfaces, icon plates and async switch. Short summaries
include the default-off behavior. Material ExpansionTile owns keyboard and
expanded-state semantics for the longer explanations; each card has its own
PageStorage key, independent of the section's scroll offset.

The native stack-memory warning is outside the disclosure and remains visible
when report details are closed. The text distinguishes scrubbed report
metadata from native memory, which bypasses the scrubber (ADR 0035). A build
without a reporting destination keeps the crash-report switch disabled and
explains its availability. Read receipts keep their independent bridge write
and mutual-receipt rule.

The shared card adapts its icon/toggle header to narrow windows and enlarged
text. It keeps the same Flexible child across layouts so a resize during a
pending write cannot recreate the switch or trigger another consent read.
Long summaries move below the switch row at narrow content widths. Errors
use theme text styles and a live semantics region. Consent, SDK lifecycle,
default values, write guards and rollback are unchanged.
The shared switch theme uses fg2 for an enabled, off thumb so it remains
distinct from the dark track; selected thumbs retain mossInk.

Widget checks use the real CrashReporting controller with ScriptableBridge
storage and a local SDK in test/support/privacy.dart. They cover missing
reporting availability, pending/failed reads, SDK-start rollback, independent
receipt writes and failures, disclosure independence, saved receipt state,
section scroll/expansion return, resize during a write, and Russian at 390px
and 320px with doubled text.
Card/tile widget trees and test registration use the existing declarative-tree
exception; interaction bodies and handlers remain below 50 lines.

Privacy verification: formatting is clean across 447 Dart files; Flutter
analysis reports no issues. The full suite passes 1067 tests with five existing
native-library skips. Changed production executable lines are 77/77 (100%);
changed branches are 16/16 (100%), intersecting LCOV with added/modified Dart
lines. The Android arm64 debug APK builds. Production-themed captures were
inspected at 1200×800, 390×844 and 320×844 with doubled text, including on,
off, unavailable and expanded states. Native device behavior and delivery to
Sentry remain for runtime review; widget checks substitute local SDK callbacks.

Privacy changes settings_content.dart, adds privacy_settings_section.dart and
settings_toggle_card.dart, and updates crash_reporting_toggle.dart,
read_receipts_toggle.dart, async_switch_tile.dart, mosh_theme.dart and both ARB
files. Tests live in privacy_settings_section_test.dart and test/support/privacy.dart.
The architecture map, ADR 0035 and this guide describe the result. No native
API, storage schema, dependency or reporting data flow changes.

## About

About uses one existing SettingsSurface with a moss shield plate, Mosh identity
and the real installed version/build number. It reads package_info_plus through
app_package_info_provider.dart, so command-line build overrides are reflected
without a hardcoded version. Version loading and failure have visible localized
text. A missing build number shows only the version; a missing version is
unavailable. The provider auto-disposes on leaving About, letting a failed read
retry on return. Successful package reads retain the plugin's own cache.

The short protection summary explicitly distinguishes OpenMLS private chats
and groups from public channels without end-to-end encryption. Per the local
copy review, a short explanation of Moss delivery and public-tracker discovery
is visible directly in the card. The redundant public-channel sentence and
separate anonymity warning were removed along with the protection disclosure.
No global security/connectivity status, licence, changelog or updater action
is introduced. Existing theme text, card padding and shapes wrap on phones
and enlarged text. Declarative widget-tree nesting uses the existing exception;
methods and interaction test bodies remain below 50 lines.

Initial About verification: formatting is clean across 449 Dart files and Flutter
analysis reports no issues. The full suite passes 1076 tests with five existing
native-library skips. Changed production executable lines are 35/35 (100%);
changed branches are 9/9 (100%), intersecting LCOV with added/modified Dart
lines. Nine focused About checks cover the plugin API with mock metadata,
version/build overrides, missing values, loading/failure, disposal, retry on return, disclosure
and scroll persistence, and Russian narrow/enlarged-text layouts. Captures were
inspected at 1200×800, 390×844 and 320×844 with doubled text, including loaded,
loading, unavailable and expanded states. Physical Windows/Android review
remains separate from widget layout verification. The Android arm64 debug APK
builds successfully.

Copy-review follow-up removes the protection disclosure and its unused
localization entries. Its obsolete expansion/scroll test is removed; the
remaining eight About checks retain version/lifecycle/retry and narrow-layout
coverage with the direct network paragraph. Formatting across 449 Dart files
and analysis are clean. The full suite passes 1075 tests with five existing
native-library skips. The one changed executable Dart line is covered;
changed branch coverage is not applicable. Updated captures were inspected at
1200px, 390px and 320px with doubled text.

Changed files are about_settings_section.dart, app_package_info_provider.dart,
both localization ARBs and about_settings_section_test.dart. The plan,
architecture map and this guide describe the result. No Rust API, schema or
dependency changes.

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

Connection adds `settings_disclosure.dart` and `bind_interface_controls.dart`.
The unused `connection_diagnostics.dart` was removed after the user's review.
It updates `connection_settings_section.dart`,
`settings_card.dart`, `settings_content.dart`, `bind_interface_field.dart`,
`read_receipts_toggle.dart`, `desktop_app_relauncher.dart` and both ARB files.
Tests cover lazy adapter reads, collapse preservation, section reopening,
scroll preservation, loading/error/retry, unavailable adapters, repeated switching, restart
failure, disposal during a write, the receipt's Privacy write path and 320px
layout with doubled text.

The VPN restart correction updates `bind_interface_field.dart`,
`mosh-core/src/api/shared_runtime.rs`, adapter and Connection tests, this
document, the architecture map and ADR 0016. It adds
`test/features/vpn/bind_interface_restart_test.dart` and
`mosh-core/tests/vpn_bypass_restart.rs`.
