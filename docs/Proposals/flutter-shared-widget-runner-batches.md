# Bounded shared-widget runners

Starting commit: `a75e58f5cbb4bd015b985eff4eff08424efc523c`. Fourteen standalone
widget libraries move to sibling `*_cases.dart` files, unchanged byte-for-byte,
and five small `*_test.dart` drivers register them with the existing
`group('stem', stem.main)` pattern. All **56 cases and assertions remain**.
Worker entry points fall **14 → 5** in this scope and **255 → 246** globally,
with **1890 passed and the same four native skips**. This follows the separate
[three-registration UI consolidation](flutter-ui-merge-test-cleanup.md);
no further test or assertion is deleted here.

## Scope and source proof

- SHA-256 comparisons prove all fourteen case files equal their baseline source blobs.
  Imports, fixtures/classes, callbacks, assertions and every input/clock event retain their bytes.
- Same-folder moves retain every relative import. No production/helper/dependency,
  timeout/retry/platform gate or CI concurrency change. No case deletion or merged test body.
- Each synchronous driver imports sibling namespaces and registers one scoped group per
  case library; it adds no setup/teardown or shared fake. Library privacy remains intact.
- Existing case-owner policy passes on the actual complete source set: exactly one
  scoped owner per moved main. Candidate sources have no hazardous expressions to move.
- Preservation uses the explicit full identity mapping below, including result/skip
  state and duplicate multiplicity; a green count alone is not the source proof.

## Bounded composition

Baseline body sums below budget worker size; they are overlapping test intervals,
not command wall/CPU and not candidate measurements. No giant serial runner is added.

| Driver | New path under `test/features/shared/` | Cases | Baseline Σ bodies (s) |
| --- | --- | ---: | ---: |
| A | `shared_dialog_focus_test.dart` | 7 | 3.967 |
| B | `shared_hit_targets_test.dart` | 10 | 4.022 |
| C | `shared_confirm_visuals_test.dart` | 12 | 4.281 |
| D | `shared_feedback_test.dart` | 8 | 4.140 |
| E | `toasts/toast_contract_test.dart` | 19 | 2.913 |

## Measurements and verification

Flutter 3.44.7 stable (`84fc5cbb`), Dart 3.12.2, the same shared Linux host,
warm caches and unchanged default concurrency. Root runs benchmarks sequentially;
reviewers only read source or prepare private audit notes. Other agents' server
work remains outside our control. Three scoped pairs use A/B, B/A, A/B order;
all 56 identities/outcomes match. Seed 42 also passes all 56.

Scoped commands (before/after, Bash brace expansion):

```sh
flutter test --machine test/features/shared/{mosh_dialog,focus_ring,avatar,hit_area,media_time_label,press_scale,confirm_dialog,modal_focus_trap,on_accent_contrast,async_switch_tile,chat_error_banner,persistence_warning_banner}_test.dart test/features/shared/toasts/{toast_host,toaster}_test.dart
flutter test --machine test/features/shared/{shared_dialog_focus,shared_hit_targets,shared_confirm_visuals,shared_feedback}_test.dart test/features/shared/toasts/toast_contract_test.dart
```

The second command also passes with `--test-randomize-ordering-seed=42`.
Each report records the expanded actual argument array; no test filters are used.

| Measurement (seconds) | Fourteen workers | Five workers |
| --- | ---: | ---: |
| Scoped median command wall, launcher/hooks included | 13.051 | 9.916 |
| Scoped median completed-child CPU | 45.681 | 26.734 |
| Scoped median sum of file spans | 69.066 | 33.744 |
| Scoped median sum of loading spans | 53.228 | 23.659 |
| Scoped median sum of visible body spans | 16.137 | 9.743 |

Individual scoped samples:

- Before: wall 13.051 / 13.372 / 12.786; CPU 45.681 / 46.188 / 44.281.
- After: wall 9.848 / 10.355 / 9.916; CPU 26.734 / 27.831 / 26.110.

Scoped median wall is 24.0% lower and child CPU 41.5% lower. This is the measured
cost of running these 56 cases, not an extrapolation to the full suite or CI.

Complete comparison uses identical `flutter test --machine` commands in A/B/B/A
order. Initial A is the immediately preceding full-retained-after capture;
all test/production source bytes match the starting commit (only audit notes
changed between capture and that commit).

| Source | Passed / skipped | Workers | Wall s | Child CPU s | File spans s | Loading s | Bodies s |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Before A1 | 1890 / 4 | 255 | 149.479 | 1218.500 | 1145.973 | 492.062 | 652.353 |
| After B1 | 1890 / 4 | 246 | 132.814 | 1084.156 | 1011.733 | 427.638 | 582.512 |
| After B2 | 1890 / 4 | 246 | 126.792 | 1025.803 | 966.552 | 417.196 | 547.816 |
| Before A2 | 1890 / 4 | 255 | 128.214 | 1031.258 | 977.926 | 428.457 | 548.040 |

Wall measures the complete command; CPU is resource use of completed benchmark
descendants. File/loading/body intervals overlap under parallel scheduling and
must not be summed into total wall or interpreted as CPU. Warm caches and other
agents on this shared server can affect observations. Scoped savings establish
only this module result. The original full suite itself moved from 149.479s to
128.214s and CPU 1218.500s to 1031.258s. The closest B2/A2 comparison observes
wall 126.792s vs 128.214s and CPU 1025.803s vs 1031.258s, but the ranges overlap;
these runs do **not** establish a repeatable whole-suite speedup. In particular,
do not attribute the first 11% elapsed difference to this patch. Retain the small
registration-only change for its repeatable 56-case resource saving and nine
fewer worker entry points, with no fixture or assertion changes.

All four full runs have zero failures. Exact runtime Counters normalize only the
56 ledger identities and preserve all 1890 passed cases, four native skip paths,
reasons and multiplicities; no other name/outcome changes. Source hashes and
two independent read-only reviews establish assertion preservation separately
from those green executions. The guarded A/B switch changes only the reviewed
33-path union and never the index; final hashes match the reviewed candidate.

- `flutter analyze`: no issues, including configured unused-import, unused-element
  and dead-code diagnostics; no additional unused-code tool is configured here.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  810 files, zero changes.
- `python3 -B scripts/test-policy.py`: passes with the actual final case owners.
  All seven existing executable policy examples pass; the invalid-baseline example
  deliberately prints its Git error. No policy exception or historical allowance
  changes, no new lint implementation or new tests of test deletion.
- `git diff --check`: passes. Every moved source matches its baseline blob, and
  production, existing shared helpers, dependency/lockfiles, CI and AGENTS have
  no diff from the starting commit.

## Isolation and consumers

- Every old main synchronously registered `testWidgets`, so every selected old
  process already initialized the widget binding. Main bodies only register tests
  or declare local helper functions; none performs bare registration-time work.
- No imported case-driver tree, file annotations/metadata, `setUpAll`/`tearDownAll`,
  FontLoader, real HTTP, native initialization, appRouter or process-global probe.
- Dialog FocusNodes are disposed; modifiers released; changed physical view values
  reset. Toast view/accessibility overrides have per-test cleanup, explicit provider
  containers and Toasters are disposed, and the created mouse pointer is removed.
- The time-label suite imports the viewer but constructs only the label; it never
  initializes native playback. Existing timer/motion boundary frames remain intact.
- Source-consumer scan covered test/native/integration/lib/scripts/.github roots:
  865 files, with no import/export/part or filename consumer of the fourteen old leaves.
  Active docs only: `docs/Features/toasts.md` references the old two toast files.
  Those references now name the case libraries and their shared toast command.
  Historical audit paths stay historical.
- Existing image-preview drivers, native/media/HTTP probes, voice-plugin/filesystem
  suites, date-format global setup and frozen timeout/wait/skip cases are excluded.
  This repeats neither rejected Dart CLI nor RailPane fixture experiments.

## Contract and identity ledger

All rows are **KEEP / MOVE**. Module `M` means original suite
`test/features/shared/M_test.dart` and unchanged new library `M_cases.dart`.
The module table supplies driver `D` and prefix `P`. For every full runtime name
`N` in the following table, the exact identity map is
`(old suite, N, success, skipped=false, reason=null)` →
`(D, P + " " + N, success, skipped=false, reason=null)`. No nested name is shortened.
The driver paths resolve through the A–E table; toast module prefixes omit `toasts/`.

| Module M | Prefix P | Driver | Cases | Protected contract |
| --- | --- | --- | ---: | --- |
| `mosh_dialog` | `mosh_dialog` | A | 5 | Repeated Escape/route preservation; focus; exact motion frames; reduced motion; narrow text fit |
| `focus_ring` | `focus_ring` | A | 1 | Tab draws and clears the focus ring |
| `avatar` | `avatar` | A | 1 | Initials contrast, non-accent color and font size |
| `hit_area` | `hit_area` | B | 5 | Padded target sizes and actual outside-glyph taps for five controls |
| `media_time_label` | `media_time_label` | B | 3 | Time format, tabular figures and long-label bounds |
| `press_scale` | `press_scale` | B | 2 | Pointer-down/up and disabled behavior |
| `confirm_dialog` | `confirm_dialog` | C | 7 | Confirm/cancel results; repeated/modifier Escape; backdrop/system back |
| `modal_focus_trap` | `modal_focus_trap` | C | 1 | Forward/backward focus wraparound |
| `on_accent_contrast` | `on_accent_contrast` | C | 4 | Danger foreground tokens and actual banner/button use |
| `async_switch_tile` | `async_switch_tile` | D | 1 | No overlapping pending writes; completion re-enables |
| `chat_error_banner` | `chat_error_banner` | D | 4 | Message, retry visibility and retry action |
| `persistence_warning_banner` | `persistence_warning_banner` | D | 3 | Both warning classes and accessible announcement |
| `toasts/toast_host` | `toast_host` | E | 11 | Rendering, announcements, dismiss/hover/swipe, layout, scope/disposal |
| `toasts/toaster` | `toaster` | E | 8 | Queue/repeat/lifetime/pause/dismiss clock contracts |

| Module M | Full original runtime name N — KEEP / MOVE |
| --- | --- |
| `mosh_dialog` | `a second Escape during close preserves the underlying page` |
| `mosh_dialog` | `dialog traps Tab focus and returns it to the opening control` |
| `mosh_dialog` | `modal enters from .96 and leaves within 150ms` |
| `mosh_dialog` | `reduced motion opens and dismisses without a transition` |
| `mosh_dialog` | `long content and actions fit a narrow enlarged-text dialog` |
| `focus_ring` | `Tab onto the control draws the ring; leaving clears it` |
| `avatar` | `initials are non-accent text at 4.5:1 on the plate, 11.5px` |
| `hit_area` | `the send button catches taps just outside its 32px paint` |
| `hit_area` | `the paperclip picker is at least a 40px target` |
| `hit_area` | `the fingerprint lock target reaches past its 15px glyph` |
| `hit_area` | `the confirm-dialog close X is at least a 40px target` |
| `hit_area` | `the org offer dismiss X is at least a 40px target` |
| `media_time_label` | `renders m:ss / m:ss with tabular figures` |
| `media_time_label` | `zero position renders as 0:00` |
| `media_time_label` | `long durations stay on one line inside the 80px slot` |
| `press_scale` | `PressScale scales down on pointer down and restores on up` |
| `press_scale` | `PressScale is a no-op when enabled is false` |
| `confirm_dialog` | `Escape cancels once per press with or without modifiers` |
| `confirm_dialog` | `showConfirmDialog returns true on confirm` |
| `confirm_dialog` | `showConfirmDialog returns false on ghost cancel` |
| `confirm_dialog` | `showConfirmDialog returns false on close-X` |
| `confirm_dialog` | `showConfirmDialog returns false on backdrop tap` |
| `confirm_dialog` | `showConfirmDialog returns false on Esc` |
| `confirm_dialog` | `showConfirmDialog returns false on Android system-back` |
| `modal_focus_trap` | `ModalFocusTrap cycles focus on Tab and Shift+Tab` |
| `on_accent_contrast` | `theme on-danger tokens are dark ink, not near-white fg1` |
| `on_accent_contrast` | `the error banner body reads the on-container token` |
| `on_accent_contrast` | `the confirm danger button label reads the on-error token` |
| `on_accent_contrast` | `a dark custom dangerColor flips to the light foreground` |
| `async_switch_tile` | `a tap during a pending write is ignored` |
| `chat_error_banner` | `renders the message text` |
| `chat_error_banner` | `shows the Retry button when onRetry is non-null` |
| `chat_error_banner` | `hides the Retry button when onRetry is null` |
| `chat_error_banner` | `tapping Retry fires the callback` |
| `persistence_warning_banner` | `renders localized title + body for the unavailable branch` |
| `persistence_warning_banner` | `renders localized title + body for the error branch` |
| `persistence_warning_banner` | `announces title and body once, without the icon` |
| `toasts/toast_host` | `a toast shows once and closes on its timer` |
| `toasts/toast_host` | `screen readers hear each toast, errors interrupt` |
| `toasts/toast_host` | `the close button dismisses and is named` |
| `toasts/toast_host` | `a swipe toward the edge dismisses, a short one springs back` |
| `toasts/toast_host` | `hovering fans the stack out and holds its timers` |
| `toasts/toast_host` | `taps around the stack reach the screen below` |
| `toasts/toast_host` | `phones show toasts above the composer` |
| `toasts/toast_host` | `reduced motion swaps toasts in place` |
| `toasts/toast_host` | `closing the app leaves no toast timer behind` |
| `toasts/toast_host` | `a replaced scope shows its own toasts` |
| `toasts/toast_host` | `an old removal cannot erase the replacement stack height` |
| `toasts/toaster` | `a burst queues past the stack instead of dropping messages` |
| `toasts/toaster` | `a folded toast keeps its lifetime until it can be read` |
| `toasts/toaster` | `a burst can evict an oldest toast that was already read` |
| `toasts/toaster` | `a burst waits while the pointer holds the expanded stack` |
| `toasts/toaster` | `a repeat comes back to the front instead of stacking a copy` |
| `toasts/toaster` | `errors stay longer than confirmations` |
| `toasts/toaster` | `a paused stack holds its toasts and grants a full lifetime after` |
| `toasts/toaster` | `dismissing frees a slot for the waiting toast at once` |

Raw snapshots, per-file eligibility/cleanup proofs, hashes and exact 56-identity
mapping: `.git/test-audit/selection-rail-next/shared-batch-candidate/`.
Run reports and commands: `.git/test-audit/shared-widget-batches/`.
Remaining limits: shared-host variance, Linux-only measurements and untested
real-device/native behavior. The same four native gates remain; native/device
and Rust suites were not run because their sources and process boundaries did
not change. No production lines changed, so lib-only coverage is not reported
as coverage of these registration entry points. Nothing was pushed or deployed.
