# Flutter UI cleanup evidence

Baseline and measurements: [test suite audit](test-suite-cleanup.md).
The scope includes the Flutter UI suites, following the user's references to
[t3code's test purge](https://github.com/pingdotgg/t3code/pull/22557) and
[its timeout/skip guardrails](https://github.com/pingdotgg/t3code/pull/22560).
Their percentages are not targets here. Timer use, mocks and short implementations
are not deletion criteria on their own.

## Contracts and retained representatives

The case ledger below names every removed or consolidated runner path. These
references explain the corresponding decision; source and history were read, not
inferred from a green run. Three reviewers worked read-only with separate scopes;
root owned all edits. Cross-review restored the same-kind/two-DM highlight test:
its proposed replacement only checked different kinds and was insufficient.

| Ref | Files under `test/features/` | Contract, decision and specific evidence |
| --- | --- | --- |
| V | `onboarding/first_run_viewports_test.dart` | MERGE 48→18. Keep all three steps/actions/persistence checks at six explicit `(size, scale)` representatives. `SetupSizing` branches on compact padding, stacked layout and artwork visibility, not on every Cartesian size/scale sample. History `53d2e9d4` added a broad polish sweep, not a separate regression for each sample. |
| I | `onboarding/first_run_responsive_test.dart` | MERGE equal-inset cases 9→3: keep `SetupStep.name has equal outer insets at` each of the same three sizes. Card/viewport inset calculations do not branch on step. This retains the `b2a855a9` regression. All steps remain in viewport usability checks; keyboard reachability, unsaved input, scroll/card behavior and exact 15px label regression `165fab59` remain. |
| T | `onboarding/first_run_transition_test.dart` | DELETE six screenshot frame sweeps. Repeated 16-frame no-exception assertions plus final fade/unblocked checks add no separate state transition. Keep precise crossfade/restoration/retargeting/rapid requests, outgoing input exclusion, reduced motion and disposal tests. Keep actual forward/Back workflows in `first_run_wizard_test.dart`. Read `e05f7af9`, `eb9fa265`, `8901e9b1`, `57179f34`. |
| A | `onboarding/first_run_assets_test.dart` | DELETE three fixed-PNG alpha sampling tests and file. Tests read static image channels/pixels via `image`, without app logic or a known separate regression (`82f123bb`). Asset files stay; the real wizard precaches/renders them in retained UI suites. Loss of automatic artwork-transparency inspection is intentional. |
| P | `onboarding/start_preview_test.dart`; `shared/toasts/toast_motion_preview_test.dart` | DELETE scratch previews and file-local screenshot/font/shell helpers. Default runs return without assertions; opt-in runs only export frames. Toast helper disposal test (`7582b4d7`) protects only the deleted `_capture` helper, whose resource lifetime disappears. Actual toaster/host/app suites retain expiry, pausing, announcements, disposal, duplicate-toast and closed-chat failures. Remove obsolete manual-preview commands from feature docs. |
| S | `onboarding/start_menu_test.dart` | DELETE six duplicate card/Back cases. `chat_create_screen_test.dart`, `group_create_screen_test.dart`, `channel_join_screen_test.dart` open the same cards through `pumpStartStep` and retain `Back returns to the start menu` plus successful/error workflows. KEEP both Join-with-link cases: direct `/join` tests exercise a different navigation surface. |
| C | `onboarding/chat_create_screen_test.dart`; `onboarding/group_create_screen_test.dart` | DELETE initial prop-render smoke. Retain chat `tapping Create calls inviteFlowProvider.create() and surfaces the URI`, group validation/create/reset/error/open cases. Controls must exist for those interactions; static lead copy has no separate rule. Remove unused `_groupStepBody`. |
| N | `settings/settings_screen_test.dart` | DELETE absence-of-old-icons snapshot. It pins a removed feature, not a live settings contract. Seven navigation/state-restoration scenarios and all settings persistence/privacy/error/update suites remain. Remove its local `_noop` and import. |
| D | `shared/confirm_dialog_test.dart` | DELETE direct prop/callback/style mirrors. `showConfirmDialog returns true on confirm` and the five false-result cases exercise the actual controls/callbacks through Navigator completion. Explicit label/color/header constants have no custom logic. Preserve `Escape cancels once per press with or without modifiers` (`99205db8`), narrow/enlarged dialog fit and on-accent contrast behavior. |
| R | `routing/chat_redesign_layout_test.dart` | MERGE details lifecycle matrix 18→9. `ConversationScreen` shares details mounting/toggling for all kinds; its branch is 1280px, shell branch is 580px. Keep Alice at 320/390/581/1280/1536, plus group/channel at 390 and 1536. Thus minimum phone, immediately-above-mobile, dock boundary and roomy desktop remain, as do all six existing visual export views. Remove 800px repeat and kind repeats on the same shared branch. Details reset-on-chat-change and Ctrl+K scenarios remain. This refines the initial conservative KEEP after examining the common implementation. |
| E | `conversation/message_selection_row_controls_test.dart` | MERGE 27→9 on explicit Windows desktop. Every kind × download/cancel/retry remains, with focus-node preservation, selection blocking and restored Enter activation. `ExcludeFocus`/`AbsorbPointer` gate has no OS branch (`c069cb8a`, `60476d49`); this test never sends Ctrl/Meta or selects native text. |
| O | `conversation/attachment_card_video_overlay_test.dart` | MERGE three cases into `attachment_card_preview_test.dart`; delete copied harness/PNG fixture. Existing image-with-preview case now asserts no play glyph; video-with-preview asserts the play glyph. Existing no-thumbnail video case already checks no Image, one play glyph, semantics and actual `onOpen` descriptor. No MIME boundary lost. |
| W | `shared/voice_composer_timer_test.dart` | MERGE into real permission-flow tests, delete token-only file. `tap with permission granted starts the recording phase` asserts rendered timer font features and dot danger color; `stop lands in review; send hands over the VoiceSend` asserts the rendered review timer. Preserves `894ee227` consumer wiring rather than only a constant. Review transition is settled after stopping so the outgoing recording timer cannot be confused with the review timer. No new test helper or timeout. |
| B | `voice_call/cpal_voice_playback_test.dart`; `voice_call/cpal_ringtone_test.dart` | DELETE four compiler/class-identity checks and both files. Classes explicitly `implements` their seams; typed production overrides are actual compile-time consumers. Tests never call `start`, decode or open a device. Introductions `56e8e4b8`, `ebaaf705`; no runtime regression removed. |
| F | `voice_call/voice_capture_test.dart`; `voice_call/voice_playback_test.dart` | DELETE three static conformance checks. Capture unsupported flag has a retained explicit test. Playback helper returns literal 2 after inert calls; it observes no delivery. Retain actual no-op feed, callback absence and idempotent stop tests. Histories `b4a22c6f`, `f46322c2`. Remove unused `call_drain` import and stale seam-test comments. |
| M | `voice_call/incoming_call_modal_test.dart`; `voice_call/outgoing_call_modal_test.dart` | DELETE two duplicate prop snapshots. In each file `keeps the modal alive when the ringtone device is unavailable` retains identical Alice/status assertions through the same unconditional build path. Lifecycle/cleanup, controls, Escape and error behavior stay. Introductions `a53ffa9e`, `1c89c48c`. |
| G | `fingerprint/fingerprint_emoji_test.dart` | DELETE cardinality/self-equality checks. All three exact inputs retain literal four-item vectors; pure mapping's same-call comparison provides no extra oracle. Preserve empty input, hex/nonhex/odd-char vectors, byte-change and case behavior. History `25443806` (#11). |
| L | `fingerprint/fingerprint_lock_test.dart` | MERGE tooltip/icon checks before the tap in `tapping the lock opens the dialog with emoji, hex, hint`. Keep empty-fingerprint visibility gate separately. No security indicator state is guessed or removed. |
| K | `conversation/message_copy_test.dart`; `message_selection_mode_test.dart`; `message_focus_test.dart`; `message_context_menu_test.dart` | MERGE 17 OS repeats. App-owned pointer/menu/Enter cases use explicit Windows. Direct app copy shortcuts retain Windows Ctrl and macOS Meta; Linux repeats Ctrl in `messageCopyShortcut`. Preserve every kind, ordering, focus/tint and menu-key scenario. Read `991a3ab0`, `c069cb8a`, `60476d49`, `9d59a0da`. Native text-selection variants remain: Flutter has a distinct Linux consecutive-tap cycle, so Linux is not globally equivalent to Windows. |

Viewport representatives retained for **every** SetupStep (effective height
excludes the titlebar; 1024×768 was rejected because it still yields compact
padding after that subtraction):

| Size | Scale | Branch class |
| --- | --- | --- |
| 320×568 | 2 | Minimum portrait, compact stacked, hidden artwork |
| 568×320 | 2 | Short landscape, compact stacked, hidden artwork |
| 768×1024 | 2 | Compact stacked with artwork |
| 800×450 | 1 | Compact two columns, short/narrow viewport |
| 1920×1080 | 2 | Roomy padding, stacked because of large text |
| 1920×1080 | 1 | Roomy two columns with artwork height caps |

The full native text selection, fragment-copy, drag, timed-third-click,
selection-clearing, screen-reader overlay and mobile-handle variants remain.
`conversation_keyboard_send_test.dart` keeps every platform: `b743f14a` / PR #52
fixed platform-dependent EditableText input-connection/focus behavior (#48).
Org accessible crowns/focus (`28882647`), roster/admin gates and offer identities,
all media/frame/native/window/privacy tests, and call races remain.

## Case ledger

Generated from completed runner reports using file plus full runner path, including
variant suffixes. MERGE can mean a removed redundant matrix sample or an assertion
moved into the retained behavior test; the contract/reference column names its
replacement.

<!-- case-ledger -->
| File | Full runner path | Decision | Contract / concrete reason and replacement |
| --- | --- | --- | --- |
| `test/features/conversation/attachment_card_video_overlay_test.dart` | `image with thumbnail does NOT render a play overlay` | MERGE | O: Same MIME boundary now checked in existing preview/open-action tests. |
| `test/features/conversation/attachment_card_video_overlay_test.dart` | `video with thumbnail renders a centered play overlay over the image` | MERGE | O: Same MIME boundary now checked in existing preview/open-action tests. |
| `test/features/conversation/attachment_card_video_overlay_test.dart` | `video without thumbnail renders an open thumb (no overlay)` | MERGE | O: Same MIME boundary now checked in existing preview/open-action tests. |
| `test/features/conversation/message_context_menu_test.dart` | `menu key and Shift+F10 support arrow navigation and activation (variant: TargetPlatform.linux)` | MERGE | K: Retain Windows app menu/pointer/Enter path; native selection variants stay. |
| `test/features/conversation/message_context_menu_test.dart` | `menu key and Shift+F10 support arrow navigation and activation (variant: TargetPlatform.macOS)` | MERGE | K: Retain Windows app menu/pointer/Enter path; native selection variants stay. |
| `test/features/conversation/message_context_menu_test.dart` | `text and file menus share styled rows and pointer placement (variant: TargetPlatform.linux)` | MERGE | K: Retain Windows app menu/pointer/Enter path; native selection variants stay. |
| `test/features/conversation/message_context_menu_test.dart` | `text and file menus share styled rows and pointer placement (variant: TargetPlatform.macOS)` | MERGE | K: Retain Windows app menu/pointer/Enter path; native selection variants stay. |
| `test/features/conversation/message_copy_test.dart` | `DM: right-click, Copy message copies the body alone (variant: TargetPlatform.linux)` | MERGE | K: Retain Windows pointer path or Windows Ctrl/macOS Meta app-copy branches. |
| `test/features/conversation/message_copy_test.dart` | `DM: right-click, Copy message copies the body alone (variant: TargetPlatform.macOS)` | MERGE | K: Retain Windows pointer path or Windows Ctrl/macOS Meta app-copy branches. |
| `test/features/conversation/message_copy_test.dart` | `channel: right-click, Copy message copies the body alone (variant: TargetPlatform.linux)` | MERGE | K: Retain Windows pointer path or Windows Ctrl/macOS Meta app-copy branches. |
| `test/features/conversation/message_copy_test.dart` | `channel: right-click, Copy message copies the body alone (variant: TargetPlatform.macOS)` | MERGE | K: Retain Windows pointer path or Windows Ctrl/macOS Meta app-copy branches. |
| `test/features/conversation/message_copy_test.dart` | `group: right-click, Copy message copies the body alone (variant: TargetPlatform.linux)` | MERGE | K: Retain Windows pointer path or Windows Ctrl/macOS Meta app-copy branches. |
| `test/features/conversation/message_copy_test.dart` | `group: right-click, Copy message copies the body alone (variant: TargetPlatform.macOS)` | MERGE | K: Retain Windows pointer path or Windows Ctrl/macOS Meta app-copy branches. |
| `test/features/conversation/message_copy_test.dart` | `the copy shortcut on a focused message copies its body (variant: TargetPlatform.linux)` | MERGE | K: Retain Windows pointer path or Windows Ctrl/macOS Meta app-copy branches. |
| `test/features/conversation/message_focus_test.dart` | `DM: selecting through the menu restores focus with only the selection tint (variant: TargetPlatform.linux)` | MERGE | K: Retain Windows Ctrl/macOS Meta focus/tint regression paths. |
| `test/features/conversation/message_focus_test.dart` | `channel: selecting through the menu restores focus with only the selection tint (variant: TargetPlatform.linux)` | MERGE | K: Retain Windows Ctrl/macOS Meta focus/tint regression paths. |
| `test/features/conversation/message_focus_test.dart` | `group: selecting through the menu restores focus with only the selection tint (variant: TargetPlatform.linux)` | MERGE | K: Retain Windows Ctrl/macOS Meta focus/tint regression paths. |
| `test/features/conversation/message_focus_test.dart` | `keyboard focus and menu dismissal never outline a message row (variant: TargetPlatform.linux)` | MERGE | K: Retain Windows Ctrl/macOS Meta focus/tint regression paths. |
| `test/features/conversation/message_selection_mode_test.dart` | `the copy shortcut copies picked messages oldest first (variant: TargetPlatform.linux)` | MERGE | K: Retain Windows Ctrl/macOS Meta ordering and toolbar focus paths. |
| `test/features/conversation/message_selection_mode_test.dart` | `the desktop toolbar copies picked messages oldest first (variant: TargetPlatform.linux)` | MERGE | K: Retain Windows Ctrl/macOS Meta ordering and toolbar focus paths. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `DM: selection blocks keyboard cancel download and restores it on Cancel (variant: TargetPlatform.linux)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `DM: selection blocks keyboard cancel download and restores it on Cancel (variant: TargetPlatform.macOS)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `DM: selection blocks keyboard download and restores it on Cancel (variant: TargetPlatform.linux)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `DM: selection blocks keyboard download and restores it on Cancel (variant: TargetPlatform.macOS)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `DM: selection blocks keyboard retry and restores it on Cancel (variant: TargetPlatform.linux)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `DM: selection blocks keyboard retry and restores it on Cancel (variant: TargetPlatform.macOS)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `channel: selection blocks keyboard cancel download and restores it on Cancel (variant: TargetPlatform.linux)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `channel: selection blocks keyboard cancel download and restores it on Cancel (variant: TargetPlatform.macOS)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `channel: selection blocks keyboard download and restores it on Cancel (variant: TargetPlatform.linux)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `channel: selection blocks keyboard download and restores it on Cancel (variant: TargetPlatform.macOS)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `channel: selection blocks keyboard retry and restores it on Cancel (variant: TargetPlatform.linux)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `channel: selection blocks keyboard retry and restores it on Cancel (variant: TargetPlatform.macOS)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `group: selection blocks keyboard cancel download and restores it on Cancel (variant: TargetPlatform.linux)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `group: selection blocks keyboard cancel download and restores it on Cancel (variant: TargetPlatform.macOS)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `group: selection blocks keyboard download and restores it on Cancel (variant: TargetPlatform.linux)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `group: selection blocks keyboard download and restores it on Cancel (variant: TargetPlatform.macOS)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `group: selection blocks keyboard retry and restores it on Cancel (variant: TargetPlatform.linux)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/conversation/message_selection_row_controls_test.dart` | `group: selection blocks keyboard retry and restores it on Cancel (variant: TargetPlatform.macOS)` | MERGE | E: Same Enter gate; retain this kind/control/focus scenario on explicit Windows. |
| `test/features/fingerprint/fingerprint_emoji_test.dart` | `a non-empty fingerprint renders exactly four emoji` | DELETE | G: Same inputs retain literal vectors; cardinality/self-comparison adds no oracle. |
| `test/features/fingerprint/fingerprint_emoji_test.dart` | `the same fingerprint always maps to the same emoji` | DELETE | G: Same inputs retain literal vectors; cardinality/self-comparison adds no oracle. |
| `test/features/fingerprint/fingerprint_lock_test.dart` | `lock renders with the E2EE tooltip` | MERGE | L: Icon/tooltip assertions moved before tap in retained dialog interaction test. |
| `test/features/onboarding/chat_create_screen_test.dart` | `initial state shows Create button (no lastInvite) and no InviteResult` | DELETE | C: Initial prop smoke; retained create success locates controls and verifies result. |
| `test/features/onboarding/first_run_assets_test.dart` | `devices illustration preserves transparency and translucent light` | DELETE | A: Static PNG alpha sampling; no app behavior or separate regression. |
| `test/features/onboarding/first_run_assets_test.dart` | `network illustration preserves transparency and translucent light` | DELETE | A: Static PNG alpha sampling; no app behavior or separate regression. |
| `test/features/onboarding/first_run_assets_test.dart` | `welcome illustration preserves transparency and translucent light` | DELETE | A: Static PNG alpha sampling; no app behavior or separate regression. |
| `test/features/onboarding/first_run_responsive_test.dart` | `SetupStep.device has equal outer insets at Size(1280.0, 680.0)` | MERGE | I: Step-independent card insets; retain name-step check at this same size. |
| `test/features/onboarding/first_run_responsive_test.dart` | `SetupStep.device has equal outer insets at Size(1920.0, 1080.0)` | MERGE | I: Step-independent card insets; retain name-step check at this same size. |
| `test/features/onboarding/first_run_responsive_test.dart` | `SetupStep.device has equal outer insets at Size(390.0, 844.0)` | MERGE | I: Step-independent card insets; retain name-step check at this same size. |
| `test/features/onboarding/first_run_responsive_test.dart` | `SetupStep.network has equal outer insets at Size(1280.0, 680.0)` | MERGE | I: Step-independent card insets; retain name-step check at this same size. |
| `test/features/onboarding/first_run_responsive_test.dart` | `SetupStep.network has equal outer insets at Size(1920.0, 1080.0)` | MERGE | I: Step-independent card insets; retain name-step check at this same size. |
| `test/features/onboarding/first_run_responsive_test.dart` | `SetupStep.network has equal outer insets at Size(390.0, 844.0)` | MERGE | I: Step-independent card insets; retain name-step check at this same size. |
| `test/features/onboarding/first_run_transition_test.dart` | `SetupStep.device transition frames render at Size(1280.0, 680.0)` | DELETE | T: Frame/export sweep; precise transition/state/interaction regressions remain. |
| `test/features/onboarding/first_run_transition_test.dart` | `SetupStep.device transition frames render at Size(390.0, 844.0)` | DELETE | T: Frame/export sweep; precise transition/state/interaction regressions remain. |
| `test/features/onboarding/first_run_transition_test.dart` | `SetupStep.name transition frames render at Size(1280.0, 680.0)` | DELETE | T: Frame/export sweep; precise transition/state/interaction regressions remain. |
| `test/features/onboarding/first_run_transition_test.dart` | `SetupStep.name transition frames render at Size(390.0, 844.0)` | DELETE | T: Frame/export sweep; precise transition/state/interaction regressions remain. |
| `test/features/onboarding/first_run_transition_test.dart` | `SetupStep.network transition frames render at Size(1280.0, 680.0)` | DELETE | T: Frame/export sweep; precise transition/state/interaction regressions remain. |
| `test/features/onboarding/first_run_transition_test.dart` | `SetupStep.network transition frames render at Size(390.0, 844.0)` | DELETE | T: Frame/export sweep; precise transition/state/interaction regressions remain. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.device remains usable at Size(1024.0, 768.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.device remains usable at Size(1024.0, 768.0) with text scale 2.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.device remains usable at Size(1280.0, 680.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.device remains usable at Size(1280.0, 680.0) with text scale 2.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.device remains usable at Size(2560.0, 1440.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.device remains usable at Size(2560.0, 1440.0) with text scale 2.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.device remains usable at Size(320.0, 568.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.device remains usable at Size(568.0, 320.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.device remains usable at Size(768.0, 1024.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.device remains usable at Size(800.0, 450.0) with text scale 2.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.name remains usable at Size(1024.0, 768.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.name remains usable at Size(1024.0, 768.0) with text scale 2.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.name remains usable at Size(1280.0, 680.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.name remains usable at Size(1280.0, 680.0) with text scale 2.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.name remains usable at Size(2560.0, 1440.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.name remains usable at Size(2560.0, 1440.0) with text scale 2.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.name remains usable at Size(320.0, 568.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.name remains usable at Size(568.0, 320.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.name remains usable at Size(768.0, 1024.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.name remains usable at Size(800.0, 450.0) with text scale 2.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.network remains usable at Size(1024.0, 768.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.network remains usable at Size(1024.0, 768.0) with text scale 2.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.network remains usable at Size(1280.0, 680.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.network remains usable at Size(1280.0, 680.0) with text scale 2.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.network remains usable at Size(2560.0, 1440.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.network remains usable at Size(2560.0, 1440.0) with text scale 2.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.network remains usable at Size(320.0, 568.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.network remains usable at Size(568.0, 320.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.network remains usable at Size(768.0, 1024.0) with text scale 1.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/first_run_viewports_test.dart` | `SetupStep.network remains usable at Size(800.0, 450.0) with text scale 2.0` | MERGE | V: Sizing branches; retain all steps at six explicit branch representatives. |
| `test/features/onboarding/group_create_screen_test.dart` | `initial state renders lead, name field, and Create button` | DELETE | C: Static lead/field/button smoke; validation/create/reset/error/open cases remain. |
| `test/features/onboarding/start_menu_test.dart` | `"Create a group" opens its step inline` | DELETE | S: Same card/Back path retained in the corresponding workflow screen suite. |
| `test/features/onboarding/start_menu_test.dart` | `"Join a public channel" opens its step inline` | DELETE | S: Same card/Back path retained in the corresponding workflow screen suite. |
| `test/features/onboarding/start_menu_test.dart` | `"Start a private chat" opens its step inline` | DELETE | S: Same card/Back path retained in the corresponding workflow screen suite. |
| `test/features/onboarding/start_menu_test.dart` | `Back from "Create a group" returns to the menu` | DELETE | S: Same card/Back path retained in the corresponding workflow screen suite. |
| `test/features/onboarding/start_menu_test.dart` | `Back from "Join a public channel" returns to the menu` | DELETE | S: Same card/Back path retained in the corresponding workflow screen suite. |
| `test/features/onboarding/start_menu_test.dart` | `Back from "Start a private chat" returns to the menu` | DELETE | S: Same card/Back path retained in the corresponding workflow screen suite. |
| `test/features/onboarding/start_preview_test.dart` | `start menu preview` | DELETE | P: Default no-op / optional assertion-free screenshot exporter. |
| `test/features/routing/chat_redesign_layout_test.dart` | `#general at 1280px: responsive details and usable chat` | MERGE | R: Shared details lifecycle; retain min phone, 581 and 1280 boundaries, all kinds at 390/1536. |
| `test/features/routing/chat_redesign_layout_test.dart` | `#general at 320px: responsive details and usable chat` | MERGE | R: Shared details lifecycle; retain min phone, 581 and 1280 boundaries, all kinds at 390/1536. |
| `test/features/routing/chat_redesign_layout_test.dart` | `#general at 581px: responsive details and usable chat` | MERGE | R: Shared details lifecycle; retain min phone, 581 and 1280 boundaries, all kinds at 390/1536. |
| `test/features/routing/chat_redesign_layout_test.dart` | `#general at 800px: responsive details and usable chat` | MERGE | R: Shared details lifecycle; retain min phone, 581 and 1280 boundaries, all kinds at 390/1536. |
| `test/features/routing/chat_redesign_layout_test.dart` | `Alice at 800px: responsive details and usable chat` | MERGE | R: Shared details lifecycle; retain min phone, 581 and 1280 boundaries, all kinds at 390/1536. |
| `test/features/routing/chat_redesign_layout_test.dart` | `Design team at 1280px: responsive details and usable chat` | MERGE | R: Shared details lifecycle; retain min phone, 581 and 1280 boundaries, all kinds at 390/1536. |
| `test/features/routing/chat_redesign_layout_test.dart` | `Design team at 320px: responsive details and usable chat` | MERGE | R: Shared details lifecycle; retain min phone, 581 and 1280 boundaries, all kinds at 390/1536. |
| `test/features/routing/chat_redesign_layout_test.dart` | `Design team at 581px: responsive details and usable chat` | MERGE | R: Shared details lifecycle; retain min phone, 581 and 1280 boundaries, all kinds at 390/1536. |
| `test/features/routing/chat_redesign_layout_test.dart` | `Design team at 800px: responsive details and usable chat` | MERGE | R: Shared details lifecycle; retain min phone, 581 and 1280 boundaries, all kinds at 390/1536. |
| `test/features/settings/settings_screen_test.dart` | `the start menu keeps creation separate from settings` | DELETE | N: Absent removed-feature icons; seven live settings navigation/state cases remain. |
| `test/features/shared/confirm_dialog_test.dart` | `explicit cancelLabel drives the ghost button + close-X` | DELETE | D: Prop/style mirror or callback already exercised by retained helper result test. |
| `test/features/shared/confirm_dialog_test.dart` | `renders title, body, confirm label, and default cancel label` | DELETE | D: Prop/style mirror or callback already exercised by retained helper result test. |
| `test/features/shared/confirm_dialog_test.dart` | `tapping the close-X calls onCancel` | DELETE | D: Prop/style mirror or callback already exercised by retained helper result test. |
| `test/features/shared/confirm_dialog_test.dart` | `tapping the confirm button calls onConfirm` | DELETE | D: Prop/style mirror or callback already exercised by retained helper result test. |
| `test/features/shared/confirm_dialog_test.dart` | `tapping the ghost cancel button calls onCancel` | DELETE | D: Prop/style mirror or callback already exercised by retained helper result test. |
| `test/features/shared/confirm_dialog_test.dart` | `the confirm button uses the danger color` | DELETE | D: Prop/style mirror or callback already exercised by retained helper result test. |
| `test/features/shared/confirm_dialog_test.dart` | `title and close button share a compact header` | DELETE | D: Prop/style mirror or callback already exercised by retained helper result test. |
| `test/features/shared/toasts/toast_motion_preview_test.dart` | `captured frames release their native images` | DELETE | P: Screenshot-only helper and its resource lifetime are removed together. |
| `test/features/shared/toasts/toast_motion_preview_test.dart` | `toast motion preview` | DELETE | P: Screenshot-only helper and its resource lifetime are removed together. |
| `test/features/shared/voice_composer_timer_test.dart` | `the recording dot paints the theme danger accent, not a raw Material red` | MERGE | W: Move timer/dot assertions to existing real recording/review flow tests. |
| `test/features/shared/voice_composer_timer_test.dart` | `the shared timer style carries tabular figures` | MERGE | W: Move timer/dot assertions to existing real recording/review flow tests. |
| `test/features/voice_call/cpal_ringtone_test.dart` | `isolated production seam test does not open an audio device` | DELETE | B: Compiler-enforced seam/class identity; never opens device. |
| `test/features/voice_call/cpal_ringtone_test.dart` | `production ringtone preserves the RingtonePlayer seam` | DELETE | B: Compiler-enforced seam/class identity; never opens device. |
| `test/features/voice_call/cpal_voice_playback_test.dart` | `CpalVoicePlaybackFactory is a VoicePlaybackFactory (polymorphic assignment compiles)` | DELETE | B: Compiler-enforced interface/tear-off conformance; never starts playback. |
| `test/features/voice_call/cpal_voice_playback_test.dart` | `CpalVoicePlaybackFactory start tear-off has the seam Future<VoicePlaybackHandle> shape` | DELETE | B: Compiler-enforced interface/tear-off conformance; never starts playback. |
| `test/features/voice_call/incoming_call_modal_test.dart` | `renders the peer label and localized status` | DELETE | M: Identical peer/status asserts retained in device-unavailable modal test. |
| `test/features/voice_call/outgoing_call_modal_test.dart` | `renders the peer label and Calling... status` | DELETE | M: Identical peer/status asserts retained in device-unavailable modal test. |
| `test/features/voice_call/voice_capture_test.dart` | `voice_capture VoiceCaptureFactory subtypes can be polymorphically assigned` | DELETE | F: Static assignment; explicit unsupported/inert-callback/idempotence tests remain. |
| `test/features/voice_call/voice_playback_test.dart` | `voice_playback VoicePlaybackFactory subtypes can be polymorphically assigned` | DELETE | F: Static assignment or constant-return local helper; no frame delivery observed. |
| `test/features/voice_call/voice_playback_test.dart` | `voice_playback VoicePlaybackHandle satisfies CallFrameSink structurally` | DELETE | F: Static assignment or constant-return local helper; no frame delivery observed. |
