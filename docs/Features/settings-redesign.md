# Settings redesign

The [approved plan](../Proposals/settings-redesign.plan.md) is delivered on
`feat/settings-redesign`, one screen per local development-build review.
Stage one implements the settings frame and Sound. The other four sections
remain available with their existing controls pending their redesign stages.

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
  Dropdowns and action menus share 12px corners, a raised background and
  clipped contents so focus and hover fills stay within the rounded menu.

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
development build. Rust APIs, dependencies and persisted schemas are unchanged.

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
