# Message selection test cost

Starting commit: `4b88d339058afc275f0f23f9e4c0f893dfa2649e` (clean tree).
Owner: this task owns the two selection test files and their documentation only.
Production, dependencies, clocks, motion, retries and timeouts are out of scope.

## Plan and contract evidence

First finish and verify `message_selection_mode_test.dart` and
`message_selection_behavior_test.dart`; do not expand into routing or voice work.
Keep full-screen wiring for all three conversation kinds, mobile draft retention,
system Back, search-filtered deletion and attachment download commands. Reuse the
existing `HostedMessageList` for shared list/selection behavior. It renders the
real `ConversationMessageListView` under the real `MessageSelectionHost`.

The three screen wrappers construct the same `ConversationScreen`; that screen
mounts `MessageSelectionHost` and `ConversationScreenBody`. The latter uses the
same list and composer for all kinds. `MessageSelectionComposer` branches on
viewport width and selection state, not kind or platform. `messageCopyShortcut`
branches between Ctrl and Cmd. The row does branch on kind for sender metadata,
so body and caption clipboard checks must still cover every kind.

Risks: omitting an integration boundary, weakening native gesture regressions,
or measuring scheduling noise as a speedup. Keep focused before/after samples,
full-run results, full case identities and a per-removal replacement ledger.
Run Flutter analysis, formatting, the existing test-policy guard, all affected
selection/menu suites and the full widget/unit suite. Analyzer unused-code
diagnostics are the existing unused-code check for this Dart-only change.

## Regression history reviewed

- [IVO-24](https://linear.app/ivoxygen/issue/IVO-24), initial `991a3ab0` and review
  fix `a05661b6`:
  captioned file long press must open the menu without stealing native text
  handles or attachment download controls. Keep these regressions and all their
  existing mobile variants.
- [IVO-25](https://linear.app/ivoxygen/issue/IVO-25), `9ac6a45e`, and review fix
  `a7692665`: screen-reader pick-only actions, drag lifetimes, Back, visible-only
  deletion and clipboard behavior are contracts, not smoke checks.
- [IVO-60](https://linear.app/ivoxygen/issue/IVO-60), commit `60476d49`:
  mobile action placement, circular selectors and mounted draft retention.
  Preserve all three screen integrations and the mobile platform branches on DM.
- The previous `93ef2f30` cleanup already retained Windows/macOS separately for
  Ctrl/Cmd. Both remain covered before and after toolbar focus in the merged case.

Direct Linear reads found no comments on IVO-24 or IVO-60. No tracker writes.

## Decisions and preservation

The ledger below records all 60 original runnable test paths, including platform
variants. There are no `describe` groups in either file. DELETE removes twelve
cross-product registrations, not a gesture, message shape or platform branch.
MERGE removes two standalone shortcut registrations while preserving their
original action/assertion sequence in the toolbar case on the same platform.
Each named retained test was found exactly once with a successful result in all
three focused after runs; the audit checks outcomes and name multiplicity.

Six shared case declarations (plus two toolbar variants) use one local
`_pumpSelectionList` function. It reuses `HostedMessageList`, supplies the same
DM snapshot override through `conversationSnapshotProvider` and owns/disposes
its provider container and notifier. It introduces no new widget, fake, global
fixture or production abstraction. There is no polling/composer/header setup in
that fixture. Full screens remain for the integration contracts listed above.

A temporary Dart analyzer AST edit selected declarations by file and test name;
no regex deletion was used. A separate AST token audit confirms all fourteen
other original callback bodies are identical except the documented fixture
substitution. The original standalone shortcut statements/assertion are a
sequence-preserving subset of the retained toolbar case. Its three clipboard
writes explicitly assert shortcut with list focus, toolbar click, then shortcut
with toolbar focus; both Windows Ctrl and macOS Cmd variants stay present.

### `test/features/conversation/message_selection_behavior_test.dart`

| Full test path (no describe groups) | Contract | Decision | Evidence / retained tests |
| --- | --- | --- | --- |
| `DM: captioned files open on long press (variant: TargetPlatform.android)` | Captioned attachment long press opens menu without starting download; normal download works. | KEEP | IVO-24 regression (a05661b6); keep every original mobile variant and real screen/gateway callback. |
| `DM: captioned files open on long press (variant: TargetPlatform.fuchsia)` | Captioned attachment long press opens menu without starting download; normal download works. | KEEP | IVO-24 regression (a05661b6); keep every original mobile variant and real screen/gateway callback. |
| `DM: captioned files open on long press (variant: TargetPlatform.iOS)` | Captioned attachment long press opens menu without starting download; normal download works. | KEEP | IVO-24 regression (a05661b6); keep every original mobile variant and real screen/gateway callback. |
| `DM: secondary click on a download control opens the menu without downloading` | Right-click opens menu without download; normal click still downloads. | KEEP | Preserve each kind and its real screen/gateway attachment wiring. |
| `DM: triple click copies the whole body without metadata (variant: TargetPlatform.linux)` | Whole body/caption clipboard text, no metadata. | KEEP | Keep every kind/layout on Windows and all desktop selection/shortcut branches on DM. |
| `DM: triple click copies the whole body without metadata (variant: TargetPlatform.macOS)` | Whole body/caption clipboard text, no metadata. | KEEP | Keep every kind/layout on Windows and all desktop selection/shortcut branches on DM. |
| `DM: triple click copies the whole body without metadata (variant: TargetPlatform.windows)` | Whole body/caption clipboard text, no metadata. | KEEP | Keep every kind/layout on Windows and all desktop selection/shortcut branches on DM. |
| `DM: triple click copies the whole caption without metadata (variant: TargetPlatform.linux)` | Whole body/caption clipboard text, no metadata. | KEEP | Keep every kind/layout on Windows and all desktop selection/shortcut branches on DM. |
| `DM: triple click copies the whole caption without metadata (variant: TargetPlatform.macOS)` | Whole body/caption clipboard text, no metadata. | KEEP | Keep every kind/layout on Windows and all desktop selection/shortcut branches on DM. |
| `DM: triple click copies the whole caption without metadata (variant: TargetPlatform.windows)` | Whole body/caption clipboard text, no metadata. | KEEP | Keep every kind/layout on Windows and all desktop selection/shortcut branches on DM. |
| `channel: captioned files open on long press (variant: TargetPlatform.android)` | Captioned attachment long press opens menu without starting download; normal download works. | KEEP | IVO-24 regression (a05661b6); keep every original mobile variant and real screen/gateway callback. |
| `channel: captioned files open on long press (variant: TargetPlatform.fuchsia)` | Captioned attachment long press opens menu without starting download; normal download works. | KEEP | IVO-24 regression (a05661b6); keep every original mobile variant and real screen/gateway callback. |
| `channel: captioned files open on long press (variant: TargetPlatform.iOS)` | Captioned attachment long press opens menu without starting download; normal download works. | KEEP | IVO-24 regression (a05661b6); keep every original mobile variant and real screen/gateway callback. |
| `channel: secondary click on a download control opens the menu without downloading` | Right-click opens menu without download; normal click still downloads. | KEEP | Preserve each kind and its real screen/gateway attachment wiring. |
| `channel: triple click copies the whole body without metadata (variant: TargetPlatform.linux)` | Whole body/caption clipboard text, no metadata. | DELETE | Duplicate cross-product: kind-specific metadata/layout and platform selection/shortcut branches remain exercised by the two retained cases. Retained: `channel: triple click copies the whole body without metadata (variant: TargetPlatform.windows)`; `DM: triple click copies the whole body without metadata (variant: TargetPlatform.linux)`. |
| `channel: triple click copies the whole body without metadata (variant: TargetPlatform.macOS)` | Whole body/caption clipboard text, no metadata. | DELETE | Duplicate cross-product: kind-specific metadata/layout and platform selection/shortcut branches remain exercised by the two retained cases. Retained: `channel: triple click copies the whole body without metadata (variant: TargetPlatform.windows)`; `DM: triple click copies the whole body without metadata (variant: TargetPlatform.macOS)`. |
| `channel: triple click copies the whole body without metadata (variant: TargetPlatform.windows)` | Whole body/caption clipboard text, no metadata. | KEEP | Keep every kind/layout on Windows and all desktop selection/shortcut branches on DM. |
| `channel: triple click copies the whole caption without metadata (variant: TargetPlatform.linux)` | Whole body/caption clipboard text, no metadata. | DELETE | Duplicate cross-product: kind-specific metadata/layout and platform selection/shortcut branches remain exercised by the two retained cases. Retained: `channel: triple click copies the whole caption without metadata (variant: TargetPlatform.windows)`; `DM: triple click copies the whole caption without metadata (variant: TargetPlatform.linux)`. |
| `channel: triple click copies the whole caption without metadata (variant: TargetPlatform.macOS)` | Whole body/caption clipboard text, no metadata. | DELETE | Duplicate cross-product: kind-specific metadata/layout and platform selection/shortcut branches remain exercised by the two retained cases. Retained: `channel: triple click copies the whole caption without metadata (variant: TargetPlatform.windows)`; `DM: triple click copies the whole caption without metadata (variant: TargetPlatform.macOS)`. |
| `channel: triple click copies the whole caption without metadata (variant: TargetPlatform.windows)` | Whole body/caption clipboard text, no metadata. | KEEP | Keep every kind/layout on Windows and all desktop selection/shortcut branches on DM. |
| `group: captioned files open on long press (variant: TargetPlatform.android)` | Captioned attachment long press opens menu without starting download; normal download works. | KEEP | IVO-24 regression (a05661b6); keep every original mobile variant and real screen/gateway callback. |
| `group: captioned files open on long press (variant: TargetPlatform.fuchsia)` | Captioned attachment long press opens menu without starting download; normal download works. | KEEP | IVO-24 regression (a05661b6); keep every original mobile variant and real screen/gateway callback. |
| `group: captioned files open on long press (variant: TargetPlatform.iOS)` | Captioned attachment long press opens menu without starting download; normal download works. | KEEP | IVO-24 regression (a05661b6); keep every original mobile variant and real screen/gateway callback. |
| `group: secondary click on a download control opens the menu without downloading` | Right-click opens menu without download; normal click still downloads. | KEEP | Preserve each kind and its real screen/gateway attachment wiring. |
| `group: triple click copies the whole body without metadata (variant: TargetPlatform.linux)` | Whole body/caption clipboard text, no metadata. | DELETE | Duplicate cross-product: kind-specific metadata/layout and platform selection/shortcut branches remain exercised by the two retained cases. Retained: `group: triple click copies the whole body without metadata (variant: TargetPlatform.windows)`; `DM: triple click copies the whole body without metadata (variant: TargetPlatform.linux)`. |
| `group: triple click copies the whole body without metadata (variant: TargetPlatform.macOS)` | Whole body/caption clipboard text, no metadata. | DELETE | Duplicate cross-product: kind-specific metadata/layout and platform selection/shortcut branches remain exercised by the two retained cases. Retained: `group: triple click copies the whole body without metadata (variant: TargetPlatform.windows)`; `DM: triple click copies the whole body without metadata (variant: TargetPlatform.macOS)`. |
| `group: triple click copies the whole body without metadata (variant: TargetPlatform.windows)` | Whole body/caption clipboard text, no metadata. | KEEP | Keep every kind/layout on Windows and all desktop selection/shortcut branches on DM. |
| `group: triple click copies the whole caption without metadata (variant: TargetPlatform.linux)` | Whole body/caption clipboard text, no metadata. | DELETE | Duplicate cross-product: kind-specific metadata/layout and platform selection/shortcut branches remain exercised by the two retained cases. Retained: `group: triple click copies the whole caption without metadata (variant: TargetPlatform.windows)`; `DM: triple click copies the whole caption without metadata (variant: TargetPlatform.linux)`. |
| `group: triple click copies the whole caption without metadata (variant: TargetPlatform.macOS)` | Whole body/caption clipboard text, no metadata. | DELETE | Duplicate cross-product: kind-specific metadata/layout and platform selection/shortcut branches remain exercised by the two retained cases. Retained: `group: triple click copies the whole caption without metadata (variant: TargetPlatform.windows)`; `DM: triple click copies the whole caption without metadata (variant: TargetPlatform.macOS)`. |
| `group: triple click copies the whole caption without metadata (variant: TargetPlatform.windows)` | Whole body/caption clipboard text, no metadata. | KEEP | Keep every kind/layout on Windows and all desktop selection/shortcut branches on DM. |
| `mobile caption selection handles remain draggable with a Mosh menu (variant: TargetPlatform.android)` | Native handles extend text/caption selection and copy the selected fragment. | KEEP | IVO-24 caption-handle regression; every original text/caption/mobile variant stays unchanged. |
| `mobile caption selection handles remain draggable with a Mosh menu (variant: TargetPlatform.fuchsia)` | Native handles extend text/caption selection and copy the selected fragment. | KEEP | IVO-24 caption-handle regression; every original text/caption/mobile variant stays unchanged. |
| `mobile caption selection handles remain draggable with a Mosh menu (variant: TargetPlatform.iOS)` | Native handles extend text/caption selection and copy the selected fragment. | KEEP | IVO-24 caption-handle regression; every original text/caption/mobile variant stays unchanged. |
| `mobile text selection handles remain draggable with a Mosh menu (variant: TargetPlatform.android)` | Native handles extend text/caption selection and copy the selected fragment. | KEEP | IVO-24 caption-handle regression; every original text/caption/mobile variant stays unchanged. |
| `mobile text selection handles remain draggable with a Mosh menu (variant: TargetPlatform.fuchsia)` | Native handles extend text/caption selection and copy the selected fragment. | KEEP | IVO-24 caption-handle regression; every original text/caption/mobile variant stays unchanged. |
| `mobile text selection handles remain draggable with a Mosh menu (variant: TargetPlatform.iOS)` | Native handles extend text/caption selection and copy the selected fragment. | KEEP | IVO-24 caption-handle regression; every original text/caption/mobile variant stays unchanged. |

### `test/features/conversation/message_selection_mode_test.dart`

| Full test path (no describe groups) | Contract | Decision | Evidence / retained tests |
| --- | --- | --- | --- |
| `DM: mobile actions replace the composer and keep its draft (variant: TargetPlatform.android)` | Responsive actions, ordered copy, selector position and same mounted draft. | KEEP | Keep each real screen on Android and every mobile variant on DM. |
| `DM: mobile actions replace the composer and keep its draft (variant: TargetPlatform.fuchsia)` | Responsive actions, ordered copy, selector position and same mounted draft. | KEEP | Keep each real screen on Android and every mobile variant on DM. |
| `DM: mobile actions replace the composer and keep its draft (variant: TargetPlatform.iOS)` | Responsive actions, ordered copy, selector position and same mounted draft. | KEEP | Keep each real screen on Android and every mobile variant on DM. |
| `DM: the selection bar replaces the header` | Header swap, circular checked selectors and Cancel restoration. | KEEP | Keep actual DM/channel/group screen wiring and all assertions. |
| `Escape leaves the mode` | Escape leaves the mode. | REWRITE | Real MessageSelectionArea and host keyboard handlers receive Escape in the existing HostedMessageList; assertions unchanged. |
| `Shift extends the pick from the last picked row` | Shift extends the pick from the last picked row. | REWRITE | Real SelectableMessageRow reads HardwareKeyboard Shift state and extends the real host model; count assertion unchanged. |
| `a tap anywhere on a row picks it and tints only its bubble` | a tap anywhere on a row picks it and tints only its bubble. | REWRITE | Real SelectableMessageRow handles the row tap; real ConversationMessageRow paints the tint. Existing assertions and snapshot mapping are unchanged. |
| `channel: mobile actions replace the composer and keep its draft (variant: TargetPlatform.android)` | Responsive actions, ordered copy, selector position and same mounted draft. | KEEP | Keep each real screen on Android and every mobile variant on DM. |
| `channel: mobile actions replace the composer and keep its draft (variant: TargetPlatform.fuchsia)` | Responsive actions, ordered copy, selector position and same mounted draft. | DELETE | Duplicate cross-product: composer branches only on width/selection; all screen integrations and mobile platforms remain covered by the two retained cases. Retained: `channel: mobile actions replace the composer and keep its draft (variant: TargetPlatform.android)`; `DM: mobile actions replace the composer and keep its draft (variant: TargetPlatform.fuchsia)`. |
| `channel: mobile actions replace the composer and keep its draft (variant: TargetPlatform.iOS)` | Responsive actions, ordered copy, selector position and same mounted draft. | DELETE | Duplicate cross-product: composer branches only on width/selection; all screen integrations and mobile platforms remain covered by the two retained cases. Retained: `channel: mobile actions replace the composer and keep its draft (variant: TargetPlatform.android)`; `DM: mobile actions replace the composer and keep its draft (variant: TargetPlatform.iOS)`. |
| `channel: the selection bar replaces the header` | Header swap, circular checked selectors and Cancel restoration. | KEEP | Keep actual DM/channel/group screen wiring and all assertions. |
| `group: mobile actions replace the composer and keep its draft (variant: TargetPlatform.android)` | Responsive actions, ordered copy, selector position and same mounted draft. | KEEP | Keep each real screen on Android and every mobile variant on DM. |
| `group: mobile actions replace the composer and keep its draft (variant: TargetPlatform.fuchsia)` | Responsive actions, ordered copy, selector position and same mounted draft. | DELETE | Duplicate cross-product: composer branches only on width/selection; all screen integrations and mobile platforms remain covered by the two retained cases. Retained: `group: mobile actions replace the composer and keep its draft (variant: TargetPlatform.android)`; `DM: mobile actions replace the composer and keep its draft (variant: TargetPlatform.fuchsia)`. |
| `group: mobile actions replace the composer and keep its draft (variant: TargetPlatform.iOS)` | Responsive actions, ordered copy, selector position and same mounted draft. | DELETE | Duplicate cross-product: composer branches only on width/selection; all screen integrations and mobile platforms remain covered by the two retained cases. Retained: `group: mobile actions replace the composer and keep its draft (variant: TargetPlatform.android)`; `DM: mobile actions replace the composer and keep its draft (variant: TargetPlatform.iOS)`. |
| `group: the selection bar replaces the header` | Header swap, circular checked selectors and Cancel restoration. | KEEP | Keep actual DM/channel/group screen wiring and all assertions. |
| `row controls rest while picking` | row controls rest while picking. | REWRITE | Real CopyableMessage disables its resting menu while selecting; the existing menu-absence and picked-count assertions are unchanged. |
| `screen readers only get the pick action while picking` | screen readers only get the pick action while picking. | REWRITE | IVO-25 regression a7692665 retained: the real CopyableMessage exposes the same custom semantic actions; the original pick-only assertion is unchanged. |
| `search narrows the pick to the messages it shows` | Hidden messages are excluded from the actual deletion command. | KEEP | Keep search, host and gateway command integration unchanged. |
| `system back leaves the mode before the chat` | Back exits selection before leaving chat. | KEEP | Keep real screen/PopScope integration unchanged. |
| `the copy shortcut copies picked messages oldest first (variant: TargetPlatform.macOS)` | Ordered selected-text copy with row/list focus, on Ctrl and Cmd. | MERGE | Original statement/assertion sequence retained before the toolbar click; focused-toolbar shortcut remains separately asserted afterward. Retained: `the desktop toolbar copies picked messages oldest first (variant: TargetPlatform.macOS)`. |
| `the copy shortcut copies picked messages oldest first (variant: TargetPlatform.windows)` | Ordered selected-text copy with row/list focus, on Ctrl and Cmd. | MERGE | Original statement/assertion sequence retained before the toolbar click; focused-toolbar shortcut remains separately asserted afterward. Retained: `the desktop toolbar copies picked messages oldest first (variant: TargetPlatform.windows)`. |
| `the desktop toolbar copies picked messages oldest first (variant: TargetPlatform.macOS)` | Ordered button and shortcut copy before/after toolbar focus; selection remains active. | MERGE / REWRITE | Real host/list and toolbar, now also contains original pre-toolbar shortcut sequence; expected clipboard contains three writes. |
| `the desktop toolbar copies picked messages oldest first (variant: TargetPlatform.windows)` | Ordered button and shortcut copy before/after toolbar focus; selection remains active. | MERGE / REWRITE | Real host/list and toolbar, now also contains original pre-toolbar shortcut sequence; expected clipboard contains three writes. |
| `the last deselection leaves the mode` | the last deselection leaves the mode. | REWRITE | Real row toggle and MessageSelectionHost still exit the mode when the final selected id is removed; assertions unchanged. |

## Measurement protocol

Linux, Flutter 3.44.7 / Dart 3.12.2, the same workspace and warm dependency/native
hook caches. No other suites, analyzer or Dart audit compilers ran concurrently
with measured test commands. Ordinary source inspection/report writing continued.
Raw JSON, timings, source hashes and replacement audit: `/tmp/mosh-test-audit/selection/`.

Focused command (three controls, then three final runs; pilot excluded):

```sh
flutter test test/features/conversation/message_selection_behavior_test.dart test/features/conversation/message_selection_mode_test.dart --reporter json
```

Full command: `flutter test --reporter json`. Three original/final pairs alternate
A/B, B/A, A/B. Only the two owned test files are restored byte-for-byte from the
starting commit for controls; a `finally` block restores the final implementations.
No test concurrency flags, skips or environment settings change between states.

## Results

All focused controls passed 60 tests; all focused final runs passed 46, with no
skips. Every full control passed 1946 tests with 4 existing skips; every full
final run passed 1932 with exactly the same 4 skips. No baseline or final failures.
The number of full-run process files stays 268.

| Measurement (seconds) | Before | After |
| --- | ---: | ---: |
| Focused wall samples | 16.170 / 17.287 / 17.269 | 14.787 / 14.706 / 15.242 |
| Focused median wall | 17.269 | 14.787 |
| Focused median CPU | 38.003 | 34.288 |
| Full wall samples | 138.454 / 136.115 / 140.460 | 134.558 / 134.200 / 132.797 |
| Full median wall, including launcher/hooks | 138.454 | 134.200 |
| Full median CPU, all child processes | 1131.635 | 1085.025 |
| Full sum of file spans, median | 1057.865 | 1022.561 |
| Full sum of loading spans, median | 447.284 | 436.874 |
| Full sum of visible test-body durations, median | 609.088 | 584.289 |

Measured focused median wall reduction: **14.4%**. Full median wall
reduction: **3.1%** (4.254s), full median CPU reduction: **4.1%**.
Each paired full final run was faster than its control. These are three local
warm-cache pairs, not a forecast for CI hardware or cold native builds.
File/loading/body spans overlap under parallel execution and are not total wall
time or CPU time. Medians for the separate columns need not add up.

## Validation and limits

- Focused runs have no failures or skips. The full runs preserve the four
  existing native-library gates. Every other original file/full-name/outcome/skip
  identity and duplicate-name multiplicity match, apart from the exact
  fourteen ledger registrations; counts alone are not the preservation check.
- `flutter analyze`: no issues, including the configured unused-code checks.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  800 files, no changes. Repository test-policy guard and `git diff --check` pass.
- No production code changes or new production branches. The local test fixture
  has no branches and is exercised by the rewritten cases. Test-support coverage
  is outside the default lib-only Flutter coverage report; no percentage is
  inferred from that report. Existing runtime assertions and source/contract
  audits validate the relocation and consolidation independently of green totals.
- Native/platform integration and physical input hardware are not run locally.
  Simulated platform variants do not establish OS-level pointer/IME behavior.
- Keep per-kind/platform combinations when code or a known regression combines
  them. These two matrices are not a blanket permission to prune future matrices.

Changed files:

- `test/features/conversation/message_selection_behavior_test.dart`
- `test/features/conversation/message_selection_mode_test.dart`
- `docs/Features/message-selection.md`
- `docs/testing.md`
- `docs/Proposals/flutter-message-selection-tests.md`
