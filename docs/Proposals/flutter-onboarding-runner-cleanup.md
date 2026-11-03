# Bounded onboarding runners and the pure-Dart pilot

Starting commit: `509ea48a790156f204979e8e180f612b6d35a276`, initially clean.
Performance controls use `3527701b`: the independent interrupted-download fixture
fix is constant in every complete comparison below. See the
[reproduction and mutation audit](flutter-update-download-test-cleanup.md).

Final change: retain all onboarding cases and their private fixtures, grouping
18 widget libraries under six bounded runners. The provider and real-file store
suites stay separate. Onboarding has **166 cases in 8 entry points instead of
20**, including the same 146 widget cases. Whole-suite Flutter entry points
fall **268 -> 256**, with **1921 passes and the same four native-library gates**.
No case/assertion, production code, dependency, timeout, retry or CI step changes.
The invite Dart-lane experiment is restored to its original Flutter runner.

## What the measurements establish

The repeated module command demonstrates less module work and lower module
latency. It does **not** establish a whole-suite elapsed-time improvement.
Other agents share the server and run unrelated builds. Their load was neither
controlled nor recorded as a covariate; raw full-run wall differences cannot be
attributed confidently to this patch, in either direction. Child CPU measures
only completed benchmark descendants, but cache contention and system effects
can still affect CPU observations. No environment/concurrency tuning was used.

The grouping is retained for the repeatable module savings and twelve fewer
Flutter test-worker starts. Whole-suite scheduling/critical-path effects remain
unresolved until a controlled measurement is available. Do not quote the full
wall medians below as an established speedup or regression.

## Module comparison

Command in both states: `flutter test --machine test/features/onboarding`.
Warm local pairs ran A/B, B/A, A/B without another suite or analyzer of ours
running concurrently. Every run passed the same 166 full-name/outcome identities.

| Measurement, seconds | Original 20 entry points | Grouped 8 entry points |
| --- | ---: | ---: |
| Median process wall, launcher/hooks included | 40.637 | 33.179 |
| Median completed-child CPU | 167.348 | 112.152 |
| Median sum of file spans | 241.217 | 155.964 |
| Median sum of loading spans | 96.372 | 64.852 |
| Median sum of visible case bodies | 142.718 | 92.608 |

Module wall improves **18.4%**; child CPU improves **33.0%**. Wall samples are
40.637 / 38.700 / 40.933 before and 32.639 / 33.179 / 34.404 after.

The first bounded pilot kept 48 cases in four layout libraries. Combining them
in one runner cost 25.797s wall versus 20.640s, despite lower CPU. Two runners
had 19.764s median wall versus 19.115s, with CPU 42.492 -> 34.721s. The final
experiment therefore covers the whole feature with six UI groups of 22–27
cases and two untouched unit entry points, retaining bounded parallel work.
The pilot was verified before expanding the feature scope.

## Complete pipeline observations under shared load

A = original onboarding, B = grouped onboarding, C = B plus a Dart invite lane.
Order: A/B/C/C/B/A. A and B execute `flutter test --machine`. C executes
`dart test --reporter json dart_test` followed by `flutter test --machine`;
its timing includes both commands and both startup costs. The same private
measurement dispatcher records the commands and total process wall/child CPU.
No test filters, concurrency overrides or global timeout changes were used.

All six pipelines passed **1921**, skipped the same **4** by identical full
identity/reason, and had zero errors. In C this is 21 Dart + 1900 Flutter passes,
with 255 Flutter entry points plus one Dart entry point. C's source import
changes preserve all invite parsing/runtime-validation assertions.

| Sample | Wall, seconds | Child CPU, seconds |
| --- | ---: | ---: |
| `full-original-1` | 241.088 | 1280.628 |
| `full-grouped-1` | 249.153 | 1242.449 |
| `full-dart-1` | 257.131 | 1235.376 |
| `full-dart-2` | 255.257 | 1264.586 |
| `full-grouped-2` | 275.385 | 1257.522 |
| `full-original-2` | 227.532 | 1255.646 |

| Median observation, seconds | A | B | C |
| --- | ---: | ---: | ---: |
| Median process wall, launcher/hooks included | 234.310 | 262.269 | 256.194 |
| Median completed-child CPU | 1268.137 | 1249.985 | 1249.981 |
| Median sum of file spans | 1784.623 | 2008.164 | 1943.426 |
| Median sum of loading spans | 780.097 | 835.617 | 805.335 |
| Median sum of visible case bodies | 1001.609 | 1168.942 | 1134.680 |

File/loading/body sums overlap across parallel workers; they are neither process
wall nor CPU and their medians need not add up. CLI/hook/compiler startup is
included in process wall, not inferred by summing files.

The initial 573.063s run is a correctness baseline only: a source scan of ours
partially overlapped it. A later pre-fix control and failing candidate are also
excluded from performance medians. The existing download race from that candidate
was independently reproduced on the original commit in a detached worktree,
then fixed before the complete six-run comparison. No failure was hidden.

## Dart invite lane: not retained

All 21 invite tests also pass with only their test-framework imports changed to
`package:test`. Three scoped warm pairs give wall **8.055 -> 1.890s**, CPU
**11.126 -> 2.182s**. First Dart bootstrap was 10.758s wall / 13.243s CPU and
is recorded separately, not mixed into warm medians.

For the whole pipeline, however, Flutter's CLI remains necessary and a Dart CLI
is added. B and C have essentially identical observed child-CPU medians:
**1249.985 vs 1249.981s**. Full wall samples on the shared host establish no
reliable marginal benefit. A second lane, direct dev dependency and additional
CI/policy surface are not justified for this one runner. Original invite sources
are restored byte-for-byte; no `dart_test/` tree or dependency change is retained.
This result does not rule out a larger, independently measured pure-Dart split.

## Source ownership and contract preservation

The following source moves are structural, from each listed original
`test/features/onboarding/<module>_test.dart` to sibling `<module>_cases.dart`.
Every complete moved library matches its performance-baseline Git blob
byte-for-byte, including callbacks, assertions, exact clock pumps, helpers and
imports. The only added Dart code is six synchronous registration entry points.
Each module registers through `group('<module>', module.main)`, keeping its own
fixture scope. No app/container is shared between test cases.

| Module / retained cases | Current runner / added group | Decision |
| --- | --- | --- |
| `first_run_hierarchy` / 14 | `first_run_layout_test.dart` / `first_run_hierarchy` | KEEP all case bodies |
| `first_run_responsive` / 13 | `first_run_layout_test.dart` / `first_run_responsive` | KEEP all case bodies |
| `first_run_shell_transition` / 3 | `first_run_viewport_flow_test.dart` / `first_run_shell_transition` | KEEP all case bodies |
| `first_run_viewports` / 18 | `first_run_viewport_flow_test.dart` / `first_run_viewports` | KEEP all case bodies |
| `first_run_device_pending` / 2 | `first_run_viewport_flow_test.dart` / `first_run_device_pending` | KEEP all case bodies |
| `first_run_wizard` / 19 | `first_run_entry_test.dart` / `first_run_wizard` | KEEP all case bodies |
| `pending_invitation` / 7 | `first_run_entry_test.dart` / `pending_invitation` | KEEP all case bodies |
| `first_run_network` / 12 | `first_run_flow_test.dart` / `first_run_network` | KEEP all case bodies |
| `first_run_transition` / 14 | `first_run_flow_test.dart` / `first_run_transition` | KEEP all case bodies |
| `chat_create_screen` / 7 | `conversation_creation_test.dart` / `chat_create_screen` | KEEP all case bodies |
| `group_create_screen` / 6 | `conversation_creation_test.dart` / `group_create_screen` | KEEP all case bodies |
| `channel_join_screen` / 8 | `conversation_creation_test.dart` / `channel_join_screen` | KEEP all case bodies |
| `inline_error` / 1 | `conversation_creation_test.dart` / `inline_error` | KEEP all case bodies |
| `start_menu` / 2 | `start_actions_test.dart` / `start_menu` | KEEP all case bodies |
| `start_menu_layout` / 7 | `start_actions_test.dart` / `start_menu_layout` | KEEP all case bodies |
| `start_hover` / 5 | `start_actions_test.dart` / `start_hover` | KEEP all case bodies |
| `new_session_panel` / 5 | `start_actions_test.dart` / `new_session_panel` | KEEP all case bodies |
| `invite_result` / 3 | `start_actions_test.dart` / `invite_result` | KEEP all case bodies |

`first_run_provider_test.dart` (14) and `first_run_store_test.dart` (6) are
unchanged. Real HTTP/native initialization probes outside this feature retain
separate processes and their existing gates. The existing policy guard requires
one group-scoped owner per case library; default discovery cannot silently omit
a renamed case library. Original full test paths are inventoried below; current
runtime names add the group from the table, with the original full name intact.

Verification includes the module in random order (seed 42), full original-source /
name / result / skip-reason multiplicity comparison for all six pipelines,
byte identity checks independent of green outcomes, Flutter analysis (including
existing unused-code checks), formatting and the policy guard/examples. The
interrupted-download fix independently survives 100 repetitions and rejects a
cleanup mutation. No Rust/production API changed; native/platform integration
and optional `SETUP_PREVIEW` exports were not run.

Raw commands, snapshots, hashes, all timings and exact identity checks live in
`.git/test-audit/onboarding-runners/`, `onboarding-bounded/`, `dart-invite/` and
`update-download/`. Earlier audit reports keep paths valid at their own commits;
the table above is the current source/runner map.

<details>
<summary>All 146 original widget test paths and protected contracts</summary>

| Original file + full test path | Protected contract | Decision |
| --- | --- | --- |
| `test/features/onboarding/channel_join_screen_test.dart` / `Back returns to the start menu` | Public-channel warning, input validation, normalized route and error classes | KEEP |
| `test/features/onboarding/channel_join_screen_test.dart` / `Join button is disabled when name is empty and enabled after text entry` | Public-channel warning, input validation, normalized route and error classes | KEEP |
| `test/features/onboarding/channel_join_screen_test.dart` / `a failed join is worded by the bridge error's kind` | Public-channel warning, input validation, normalized route and error classes | KEEP |
| `test/features/onboarding/channel_join_screen_test.dart` / `a failed join surfaces a persistent inline error (role="alert") and no SnackBar` | Public-channel warning, input validation, normalized route and error classes | KEEP |
| `test/features/onboarding/channel_join_screen_test.dart` / `initial state renders lead, warning, field, button, examples` | Public-channel warning, input validation, normalized route and error classes | KEEP |
| `test/features/onboarding/channel_join_screen_test.dart` / `joining opens the channel by the name the core normalized` | Public-channel warning, input validation, normalized route and error classes | KEEP |
| `test/features/onboarding/channel_join_screen_test.dart` / `tapping Join with a name entered joins via the bridge and navigates to the channel screen` | Public-channel warning, input validation, normalized route and error classes | KEEP |
| `test/features/onboarding/channel_join_screen_test.dart` / `tapping an example fills the field and enables Join` | Public-channel warning, input validation, normalized route and error classes | KEEP |
| `test/features/onboarding/chat_create_screen_test.dart` / `Back returns to the start menu` | Saved private invitations, clipboard, typed/untyped failures and real route wiring | KEEP |
| `test/features/onboarding/chat_create_screen_test.dart` / `Open chat lands on the DM the invite created` | Saved private invitations, clipboard, typed/untyped failures and real route wiring | KEEP |
| `test/features/onboarding/chat_create_screen_test.dart` / `a failed create is worded by the bridge error's kind` | Saved private invitations, clipboard, typed/untyped failures and real route wiring | KEEP |
| `test/features/onboarding/chat_create_screen_test.dart` / `a failed create surfaces a persistent inline error (role="alert") and no SnackBar` | Saved private invitations, clipboard, typed/untyped failures and real route wiring | KEEP |
| `test/features/onboarding/chat_create_screen_test.dart` / `tapping Copy writes the URI to the clipboard, toasts and flips the label` | Saved private invitations, clipboard, typed/untyped failures and real route wiring | KEEP |
| `test/features/onboarding/chat_create_screen_test.dart` / `tapping Create calls inviteFlowProvider.create() and surfaces the URI` | Saved private invitations, clipboard, typed/untyped failures and real route wiring | KEEP |
| `test/features/onboarding/chat_create_screen_test.dart` / `the inline error clears on the next successful create attempt` | Saved private invitations, clipboard, typed/untyped failures and real route wiring | KEEP |
| `test/features/onboarding/first_run_device_pending_test.dart` / `device polling failure retains proof and blocks setup until retry` | Pending device admission and retained proof after polling failure | KEEP |
| `test/features/onboarding/first_run_device_pending_test.dart` / `pending device join blocks independent continuation and Back` | Pending device admission and retained proof after polling failure | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `SetupStep.device exposes readable, labeled touch controls` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `SetupStep.device leads with one task heading on a phone` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `SetupStep.name exposes readable, labeled touch controls` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `SetupStep.name leads with one task heading on a phone` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `SetupStep.network exposes readable, labeled touch controls` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `SetupStep.network leads with one task heading on a phone` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `a failed name save remains readable and retryable with large text` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `a linked device offers one primary continue action` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `a small progress indicator labels only the current step` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `device choices have equal emphasis before choosing` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `keyboard users can open device linking with Tab and Enter` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `resizing keeps the open importer and unsaved private link` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `setup actions use the readable setup label, not the app label` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_hierarchy_test.dart` / `the task heading outranks the desktop welcome` | Headings, accessible controls, keyboard/input and readable errors | KEEP |
| `test/features/onboarding/first_run_network_test.dart` / `Back and Continue keep the unsaved adapter selection` | VPN consent, completion/restart ordering, failures/retry and unmount races | KEEP |
| `test/features/onboarding/first_run_network_test.dart` / `Windows saves completion before starting the replacement` | VPN consent, completion/restart ordering, failures/retry and unmount races | KEEP |
| `test/features/onboarding/first_run_network_test.dart` / `automatic routing never writes bypass consent or relaunches` | VPN consent, completion/restart ordering, failures/retry and unmount races | KEEP |
| `test/features/onboarding/first_run_network_test.dart` / `closing during completion save still completes and restarts` | VPN consent, completion/restart ordering, failures/retry and unmount races | KEEP |
| `test/features/onboarding/first_run_network_test.dart` / `closing during consent save still completes and restarts` | VPN consent, completion/restart ordering, failures/retry and unmount races | KEEP |
| `test/features/onboarding/first_run_network_test.dart` / `detected VPN is explained without silently enabling bypass` | VPN consent, completion/restart ordering, failures/retry and unmount races | KEEP |
| `test/features/onboarding/first_run_network_test.dart` / `failed bypass write keeps setup open and can retry` | VPN consent, completion/restart ordering, failures/retry and unmount races | KEEP |
| `test/features/onboarding/first_run_network_test.dart` / `network read failure recovers without changing consent` | VPN consent, completion/restart ordering, failures/retry and unmount races | KEEP |
| `test/features/onboarding/first_run_network_test.dart` / `resizing preserves the selected adapter and bypass explanation` | VPN consent, completion/restart ordering, failures/retry and unmount races | KEEP |
| `test/features/onboarding/first_run_network_test.dart` / `restart failure retains the saved choice and enables retry` | VPN consent, completion/restart ordering, failures/retry and unmount races | KEEP |
| `test/features/onboarding/first_run_network_test.dart` / `unavailable saved adapter must be replaced before finishing` | VPN consent, completion/restart ordering, failures/retry and unmount races | KEEP |
| `test/features/onboarding/first_run_network_test.dart` / `unsupported relaunch explains manual restart before chats` | VPN consent, completion/restart ordering, failures/retry and unmount races | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `SetupStep.device fits the first viewport at Size(1280.0, 680.0)` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `SetupStep.device fits the first viewport at Size(900.0, 700.0)` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `SetupStep.name fits the first viewport at Size(1280.0, 680.0)` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `SetupStep.name fits the first viewport at Size(900.0, 700.0)` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `SetupStep.name has equal outer insets at Size(1280.0, 680.0)` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `SetupStep.name has equal outer insets at Size(1920.0, 1080.0)` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `SetupStep.name has equal outer insets at Size(390.0, 844.0)` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `SetupStep.network fits the first viewport at Size(1280.0, 680.0)` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `SetupStep.network fits the first viewport at Size(900.0, 700.0)` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `card stays centered and illustration follows available height` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `keyboard leaves the name and continue action reachable` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `overflow scrolls inside a stationary card` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_responsive_test.dart` / `resizing to one column preserves the unsaved name` | Insets, scroll/card geometry, resize state and keyboard reachability | KEEP |
| `test/features/onboarding/first_run_shell_transition_test.dart` / `returning to device linking keeps the unfinished importer` | Mounted shell geometry and unfinished importer state | KEEP |
| `test/features/onboarding/first_run_shell_transition_test.dart` / `step changes keep the visible shell mounted at Size(1280.0, 680.0)` | Mounted shell geometry and unfinished importer state | KEEP |
| `test/features/onboarding/first_run_shell_transition_test.dart` / `step changes keep the visible shell mounted at Size(390.0, 844.0)` | Mounted shell geometry and unfinished importer state | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `Back reverses the subtle slide and restores the saved name` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `Continue crossfades the content without a blank interval` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `SetupStep.device restores without an entrance animation` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `SetupStep.name restores without an entrance animation` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `SetupStep.network restores without an entrance animation` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `a return during exit retargets without remounting the form` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `advancing on a phone keeps outgoing card geometry stable` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `enabling reduce motion during a transition removes the slide` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `outgoing Back cannot change the active step` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `outgoing controls leave semantics and keyboard traversal` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `rapid requests reveal only the latest step` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `reduced motion allows Back on the next frame without translation` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `same-step edits, resizing and failed saves do not replay motion` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_transition_test.dart` / `unmounting during motion disposes its ticker` | Real intermediate animation frames, state retention, focus/semantics and disposal | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.device remains usable at Size(1920.0, 1080.0) with text scale 1.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.device remains usable at Size(1920.0, 1080.0) with text scale 2.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.device remains usable at Size(320.0, 568.0) with text scale 2.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.device remains usable at Size(568.0, 320.0) with text scale 2.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.device remains usable at Size(768.0, 1024.0) with text scale 2.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.device remains usable at Size(800.0, 450.0) with text scale 1.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.name remains usable at Size(1920.0, 1080.0) with text scale 1.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.name remains usable at Size(1920.0, 1080.0) with text scale 2.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.name remains usable at Size(320.0, 568.0) with text scale 2.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.name remains usable at Size(568.0, 320.0) with text scale 2.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.name remains usable at Size(768.0, 1024.0) with text scale 2.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.name remains usable at Size(800.0, 450.0) with text scale 1.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.network remains usable at Size(1920.0, 1080.0) with text scale 1.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.network remains usable at Size(1920.0, 1080.0) with text scale 2.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.network remains usable at Size(320.0, 568.0) with text scale 2.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.network remains usable at Size(568.0, 320.0) with text scale 2.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.network remains usable at Size(768.0, 1024.0) with text scale 2.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_viewports_test.dart` / `SetupStep.network remains usable at Size(800.0, 450.0) with text scale 1.0` | Reachable step actions and saved progress at each viewport/text scale | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `QR link import displays proof and can cancel before approval` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `SetupStep.device fits Size(1200.0, 850.0) with enlarged Russian text` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `SetupStep.device fits Size(390.0, 844.0) with enlarged Russian text` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `SetupStep.name fits Size(1200.0, 850.0) with enlarged Russian text` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `SetupStep.name fits Size(390.0, 844.0) with enlarged Russian text` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `SetupStep.network fits Size(1200.0, 850.0) with enlarged Russian text` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `SetupStep.network fits Size(390.0, 844.0) with enlarged Russian text` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `an incoming invitation waits until setup has completed` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `approval racing cancellation preserves the linked profile` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `cancel link returns to device choices and allows another attempt` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `committed delivery disables cancellation and continuing` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `completed installation opens chats without the wizard` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `desktop places the illustration beside the name form` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `device snapshot failure offers retry before choosing a device` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `failed cancellation keeps the pairing proof and can retry` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `failed saving keeps the name form and offers retry` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `interrupted setup restores the step and supports going back` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `name is required and first-device setup completes end to end` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/first_run_wizard_test.dart` / `unreadable preferences block chats until a successful retry` | Setup gate, saved progress, device approval/cancellation and buffered invites | KEEP |
| `test/features/onboarding/group_create_screen_test.dart` / `Back returns to the start menu` | Name validation, shared invite/clipboard behavior, errors and group route | KEEP |
| `test/features/onboarding/group_create_screen_test.dart` / `Create another group returns to an empty form` | Name validation, shared invite/clipboard behavior, errors and group route | KEEP |
| `test/features/onboarding/group_create_screen_test.dart` / `Create button is disabled until a name is typed` | Name validation, shared invite/clipboard behavior, errors and group route | KEEP |
| `test/features/onboarding/group_create_screen_test.dart` / `Open group lands on the group just created` | Name validation, shared invite/clipboard behavior, errors and group route | KEEP |
| `test/features/onboarding/group_create_screen_test.dart` / `a failed create surfaces a persistent inline error (role="alert") and no SnackBar` | Name validation, shared invite/clipboard behavior, errors and group route | KEEP |
| `test/features/onboarding/group_create_screen_test.dart` / `tapping Create creates via the bridge and shows the InviteResult card` | Name validation, shared invite/clipboard behavior, errors and group route | KEEP |
| `test/features/onboarding/inline_error_test.dart` / `announces the message once as a live region` | Exactly one live semantic announcement | KEEP |
| `test/features/onboarding/invite_result_test.dart` / `copy feedback preserves button styling and disabled actions` | Readable action hierarchy, disabled/copy state and narrow setup layout | KEEP |
| `test/features/onboarding/invite_result_test.dart` / `invitation actions share typography and secondary emphasis` | Readable action hierarchy, disabled/copy state and narrow setup layout | KEEP |
| `test/features/onboarding/invite_result_test.dart` / `setup actions keep larger text and wrap within a narrow card` | Readable action hierarchy, disabled/copy state and narrow setup layout | KEEP |
| `test/features/onboarding/new_session_panel_test.dart` / `a pane shorter than its padding still lays out` | Timed transitions, viewport boundary, retained input and reduced motion | KEEP |
| `test/features/onboarding/new_session_panel_test.dart` / `a step keeps its typed text across a trip to the menu` | Timed transitions, viewport boundary, retained input and reduced motion | KEEP |
| `test/features/onboarding/new_session_panel_test.dart` / `a step slides in over the menu and settles centred` | Timed transitions, viewport boundary, retained input and reduced motion | KEEP |
| `test/features/onboarding/new_session_panel_test.dart` / `reduced motion swaps the step in place` | Timed transitions, viewport boundary, retained input and reduced motion | KEEP |
| `test/features/onboarding/new_session_panel_test.dart` / `the leaving menu stays in place while a step slides in` | Timed transitions, viewport boundary, retained input and reduced motion | KEEP |
| `test/features/onboarding/pending_invitation_test.dart` / `Back during Open keeps the start menu after native completion` | Per-invite replacement, durable admission and navigation after completion/disposal | KEEP |
| `test/features/onboarding/pending_invitation_test.dart` / `Open waits for durable native admission before navigation` | Per-invite replacement, durable admission and navigation after completion/disposal | KEEP |
| `test/features/onboarding/pending_invitation_test.dart` / `existing DM list notifications refresh native saved invitations` | Per-invite replacement, durable admission and navigation after completion/disposal | KEEP |
| `test/features/onboarding/pending_invitation_test.dart` / `failed replacement retains the original invitation` | Per-invite replacement, durable admission and navigation after completion/disposal | KEEP |
| `test/features/onboarding/pending_invitation_test.dart` / `leaving during Open never navigates the disposed creation screen` | Per-invite replacement, durable admission and navigation after completion/disposal | KEEP |
| `test/features/onboarding/pending_invitation_test.dart` / `long URI remains two visible lines and copies in full` | Per-invite replacement, durable admission and navigation after completion/disposal | KEEP |
| `test/features/onboarding/pending_invitation_test.dart` / `saved invitations survive a fresh flow and replace independently` | Per-invite replacement, durable admission and navigation after completion/disposal | KEEP |
| `test/features/onboarding/start_hover_test.dart` / `Enter on a focused row opens it` | Pointer/focus feedback, keyboard activation and reduced motion | KEEP |
| `test/features/onboarding/start_hover_test.dart` / `hovering lifts the row and edges the chevron; leaving drops it` | Pointer/focus feedback, keyboard activation and reduced motion | KEEP |
| `test/features/onboarding/start_hover_test.dart` / `reduced motion lifts the row without moving the chevron` | Pointer/focus feedback, keyboard activation and reduced motion | KEEP |
| `test/features/onboarding/start_hover_test.dart` / `reduced motion swaps the join preview at once` | Pointer/focus feedback, keyboard activation and reduced motion | KEEP |
| `test/features/onboarding/start_hover_test.dart` / `the mark stays put under the pointer` | Pointer/focus feedback, keyboard activation and reduced motion | KEEP |
| `test/features/onboarding/start_menu_layout_test.dart` / `Tab onto a row draws the focus ring` | Layout breakpoints, full translated text, keyboard focus and reduced motion | KEEP |
| `test/features/onboarding/start_menu_layout_test.dart` / `a reveal plays in, and reduced motion shows it at rest` | Layout breakpoints, full translated text, keyboard focus and reduced motion | KEEP |
| `test/features/onboarding/start_menu_layout_test.dart` / `at 1200px: side by side, with the mark` | Layout breakpoints, full translated text, keyboard focus and reduced motion | KEEP |
| `test/features/onboarding/start_menu_layout_test.dart` / `at 390px: stacked, without the mark` | Layout breakpoints, full translated text, keyboard focus and reduced motion | KEEP |
| `test/features/onboarding/start_menu_layout_test.dart` / `at 800px: stacked, with the mark` | Layout breakpoints, full translated text, keyboard focus and reduced motion | KEEP |
| `test/features/onboarding/start_menu_layout_test.dart` / `row descriptions wrap in full on a phone in Russian` | Layout breakpoints, full translated text, keyboard focus and reduced motion | KEEP |
| `test/features/onboarding/start_menu_layout_test.dart` / `the public channel sits apart, under the open heading` | Layout breakpoints, full translated text, keyboard focus and reduced motion | KEEP |
| `test/features/onboarding/start_menu_test.dart` / `"Join with a link" opens its step inline` | Inline join and Back navigation | KEEP |
| `test/features/onboarding/start_menu_test.dart` / `Back from "Join with a link" returns to the menu` | Inline join and Back navigation | KEEP |

</details>
