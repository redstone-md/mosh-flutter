# Titlebar fixture cleanup

Baseline: `f97264e6c891d9dfa125d584655cbd9c19b5f7a1`. File:
`test/features/routing/desktop_title_bar_test.dart`. Keep every test name,
assertion, gesture, native event, pending completion and controlled clock pump.

Seven caption/frame contracts need the real `DesktopWindowFrame`,
`DesktopCaptionButtons` and `DesktopWindowController`, but do not navigate or
read conversations. Their private `_frame` fixture uses existing `pumpScreen`,
the production theme, real frame/controller/router and the same 400x800 / DPR 1
geometry, with empty content. Existing default providers retain disabled
first-run gating and no active conversation, as in the original empty selection.
This avoids building the unrelated routed chat list, welcome panel and app
hosts. It keeps real widget gestures and the existing scripted native seam.

Full app preparations decrease from 13 to 6: four routed tests and both setup
states still use `MoshApp`. Test registration remains 12; no DELETE or MERGE.
The private fixture is justified by seven identical consumers and adds no shared
test infrastructure or dependency.

## Case ledger

All names are full test paths in the file above, without group prefixes.

| Full test path | Contract | Decision | Evidence |
| --- | --- | --- | --- |
| `older window events preserve the latest queued toggle` | Stale native events cannot overwrite queued caption intent. | REWRITE fixture | Real controller, events, two completion futures and exact command order stay; no route/chat assertions. History `dac5f29b`. |
| `quick caption activations serialize maximize then restore` | Pending maximize serializes restore instead of racing. | REWRITE fixture | Both pre/post-completion assertions and real button taps stay. History `dac5f29b`. |
| `GTK preference updates during setup survive initialization` | Configuration received during initialization survives. | REWRITE fixture | The same fake native setup event initializes the real controller before the frame; position/button assertions stay. |
| `320px desktop at 200% keeps caption and status hit areas` | Narrow enlarged layout preserves controls with an active chat. | KEEP | Requires actual conversation/status wiring; original full app and scale remain. History `0d369001`. |
| `narrow desktop menu returns from the chat to its list` | Titlebar menu navigates the real chat/list routes. | KEEP | Real app/router stay. |
| `narrow desktop retains one bar across chat and settings` | Window controls persist once across route changes. | KEEP | Real app and native-command assertions stay. |
| `selected chat opens real diagnostics and settings hides its status` | Selected snapshot reaches diagnostics; settings hides status. | KEEP | Real app, snapshot, drawer and route changes stay. History `0d369001`. |
| `caption supports keyboard, drag, double-click and system menu` | Keyboard/drag/menu gestures reach native window commands. | REWRITE fixture | Real frame owns all gestures, caption owns focus; all actions and 60/350ms gesture clock pumps stay. |
| `Linux respects caption sides and runtime preference changes` | Runtime GTK layout changes alter actual caption placement. | REWRITE fixture | Same real frame, controller/native event and geometry/absence assertions. |
| `macOS reserves real traffic lights and uses native double-click` | Native inset, OS-owned double-click and fullscreen events. | REWRITE fixture | Real frame/controller and exact native-command assertion stay; no fabricated traffic lights. |
| `setup and setup errors retain window actions without chat status` | First-run and disk-error states retain window controls. | KEEP | Both real `FirstRunHarness` app states stay. |
| `DPI and window events update native caption geometry and focus` | Native maximize hit region follows DPI/focus/fullscreen. | REWRITE fixture | Same theme, viewport, frame/caption hierarchy and native seam; exact 308px/2x/cleared-region assertions stay. |

## Preservation and validation

A Dart AST edit matches the seven exact file/full-name identities. A separate
AST comparison checks all twelve declarations against the immutable baseline,
allowing only `_app` -> `_frame` in those seven. Existing `_window`, `_app` and
`_inBar` helpers are unchanged. Outcome Counters compare file/full-name/result/
skip state and multiplicity, not just totals. Concurrency and external native
protocol checks remain assertions even though their platform seam is scripted.

Raw commands, JSON, stderr, wall and child CPU data live locally in
`.git/test-audit/titlebar/`. Three focused A/B, B/A, A/B pairs use the same command,
workspace and warm dependency/native-hook caches. Saved bytes plus `finally`
restoration protect the candidate during controls. No other suite, analyzer or
audit compiler runs concurrently with benchmarks.

```sh
flutter test test/features/routing/desktop_title_bar_test.dart --reporter json
```

| Focused measurement (seconds) | Before | After |
| --- | ---: | ---: |
| Wall samples | 14.733 / 16.126 / 17.518 | 13.631 / 14.182 / 14.153 |
| Median wall, launcher/hooks included | 16.126 | 14.153 |
| Median child CPU | 24.517 | 21.409 |
| Median file span, loading included | 14.015 | 11.736 |
| Median visible test-body sum | 9.284 | 6.692 |
| Passed / skipped / failed | 12 / 0 / 0 | 12 / 0 / 0 |

All three pairs favor the candidate: local median wall decreases 12.2% and CPU
12.7%. This measures the focused file, not a full-suite or CI percentage. File
spans start at loading and finish with the last suite event; body spans exclude
hidden loading/setup events. Independently computed medians need not add up.

`flutter analyze` (types/lint/unused declarations), formatting of all 800 Dart
files, test-policy and source/outcome audits pass. Production, toolchains, CI
and timing defaults stay fixed. Full-suite validation covers this fixture
together with the independent deletion-status matrix cleanup.

Risk: seven contracts no longer rebuild unrelated app hosts. The five app-level
contracts above still protect frame integration, routes, selected diagnostics,
setup and error states. Physical/native OS execution is not a widget-test claim.
