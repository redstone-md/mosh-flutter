# VPN test runner consolidation

Baseline: `eda09b950b27dd78bfabefdb23d9d1beb2cefe6f` (`test(settings): group update contract runners`).
Branch: `test/prune-low-value-suites`. Seven VPN runners become three bounded
owners, preserving all 55 cases and their assertions. Whole-suite discovery moves
from 220 to 216 runners; 1858 passes and the same four native skips remain.

VPN-folder medians improve: wall 14.821 → 11.712 s (-20.98%), child CPU
39.237 → 24.530 s (-37.48%). Full-suite medians worsen: wall 147.459 →
153.800 s (+4.30%), child CPU 1176.516 → 1186.151 s (+0.82%). Retain the
consolidation for the repeated module-cost reduction and four fewer startup
owners. A whole-suite speedup is not established; the negative full comparison
and isolated consent wall regression are retained below.

## Scope and preserved contracts

The startup cost, rather than redundant assertions, is reduced here. Controller
and adapter tests protect application routing/filtering rules; actual widget
tests protect consent gestures, pending/error states and lifetime behavior.
All 55 are KEEP; no DELETE, case MERGE or replacement claim is made.

Implementation and histories `08e22137` (owned choices, races, late completion,
remount/retry), `745bf9e0` (saved consent versus live binding, restart persistence),
`99205db8` (real dialog cancellation) and `012d2a7b` (adapter selection/APIPA)
were reviewed. Controller assertions cannot replace real field/modal gestures.

| Scope | Original files → final owner | Cases |
| --- | --- | ---: |
| Unit | `network_choice_test.dart` + `bypass_adapter_test.dart` → existing `network_choice_test.dart` | 23 |
| Binding UI | `bind_interface_field_test.dart` + `bind_interface_restart_test.dart` → `bind_interface_contract_test.dart` | 19 |
| Consent UI | `vpn_consent_modal_test.dart` + `network_choice_prompt_test.dart` + `network_choice_remount_test.dart` → `vpn_consent_contract_test.dart` | 13 |

All paths above are under `test/features/vpn/`. Six files are byte-for-byte,
mode-preserving sibling renames to `*_cases.dart`. Their fixtures stay private
to their libraries. The new drivers register synchronous `main` functions with
separate `group` scopes and are ten/twelve lines long. Unit and widget bindings
remain in separate processes; there is no global all-VPN serial runner.

Controller declarations stay in their original file. A Dart AST edit wraps its
complete original main body in `group('network_choice', ...)`; a sibling
`group('bypass_adapter', bypass_adapter.main)` registers the renamed adapter
library. The AST audit verifies all original main statements, hooks, loops,
callbacks, actions/assertions, imports and other declarations against baseline.
Independent read-only review also checks literals/comments and exact snapshot
scopes. Original controller setup/teardown cannot run on adapter cases.

Its three historical `await Future<void>.delayed(Duration.zero);` expressions
remain in their original file and test bodies with the same multiplicity. They
are retained debt, not new sleeps, moved allowances or policy exceptions.

Every controller/UI bridge is fresh and instance-local. Held consent/read/write
operations and expected failures complete inside their own cases. Old-generation
success and failure remain separate checks. The remount regression intentionally
reuses one explicitly disposed container only inside that case; ordinary teardown
removes each widget/focus/animation tree. Escape sends key-down and key-up.

No native enumeration, real process restart, disk consent write, HTTP call or
Rust singleton is exercised by these scripted traces. Real native persistence
coverage stays in the separate unchanged `mosh-core/tests/vpn_bypass_restart.rs`.
New grouping is not evidence of real OS persistence or process restart.

## Exact retained case ledger

Every row is KEEP. The new owner/name changes only the runtime module prefix;
existing nested group names, test bodies, assertions and fixtures remain.

| Original file | Full original group/test path | Protected contract | Decision / new owner + full path |
| --- | --- | --- | --- |
| `test/features/vpn/bind_interface_field_test.dart` | `a disconnected saved adapter can still be reset` | Missing saved adapter remains clearable. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field a disconnected saved adapter can still be reset` |
| `test/features/vpn/bind_interface_field_test.dart` | `adapter choice stays local until the bypass switch is enabled` | Picker selection alone does not persist; enabling saves the actual picked adapter. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field adapter choice stays local until the bypass switch is enabled` |
| `test/features/vpn/bind_interface_field_test.dart` | `disabling bypass clears the override and fires onAccept` | Disable clears consent and invokes completion callback. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field disabling bypass clears the override and fires onAccept` |
| `test/features/vpn/bind_interface_field_test.dart` | `enabling bypass records the picked adapter and fires onAccept` | Enable reaches persistence with exact adapter and invokes completion callback. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field enabling bypass records the picked adapter and fires onAccept` |
| `test/features/vpn/bind_interface_field_test.dart` | `failed relaunch retains the saved choice and restart instructions` | Restart failure preserves successfully saved choice and visible retry/restart guidance. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field failed relaunch retains the saved choice and restart instructions` |
| `test/features/vpn/bind_interface_field_test.dart` | `failed write preserves the saved bypass state: eth0` | Failed disable keeps previously saved adapter and never restarts. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field failed write preserves the saved bypass state: eth0` |
| `test/features/vpn/bind_interface_field_test.dart` | `failed write preserves the saved bypass state: null` | Failed enable keeps previously disabled state and never restarts. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field failed write preserves the saved bypass state: null` |
| `test/features/vpn/bind_interface_field_test.dart` | `no physical NIC: shows the no-NIC hint and disables the off switch` | No eligible physical adapter renders honest absence and prevents enabling. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field no physical NIC: shows the no-NIC hint and disables the off switch` |
| `test/features/vpn/bind_interface_field_test.dart` | `no saved adapter shows VPN bypass switched off` | No saved consent renders correct Off state and actionable explanation. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field no saved adapter shows VPN bypass switched off` |
| `test/features/vpn/bind_interface_field_test.dart` | `pending reads offer no actionable adapter until they complete` | Unknown pending network state disables actions until its held read completes. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field pending reads offer no actionable adapter until they complete` |
| `test/features/vpn/bind_interface_field_test.dart` | `pending write blocks duplicates and relaunches after disposal` | Pending save disables duplicate writes; persistence completion still restarts after widget disposal. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field pending write blocks duplicates and relaunches after disposal` |
| `test/features/vpn/bind_interface_field_test.dart` | `read failure offers refresh and recovers without writing` | Read error remains visibly unknown and refresh recovers without a consent write. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field read failure offers refresh and recovers without writing` |
| `test/features/vpn/bind_interface_field_test.dart` | `releasing a missing adapter offers a connected replacement` | Clearing unavailable adapter allows selecting and saving a current adapter. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field releasing a missing adapter offers a connected replacement` |
| `test/features/vpn/bind_interface_field_test.dart` | `saved adapter shows VPN bypass switched on after loading` | Saved consent renders correct On state/adapter and restart guidance. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field saved adapter shows VPN bypass switched on after loading` |
| `test/features/vpn/bind_interface_field_test.dart` | `switch saves both directions and relaunches after each write` | Enable/disable persists both choices and invokes restart each time. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_field switch saves both directions and relaunches after each write` |
| `test/features/vpn/bind_interface_restart_test.dart` | `changed bypass survives a fresh settings widget: false` | New saved consent survives full field unmount and remount. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_restart changed bypass survives a fresh settings widget: false` |
| `test/features/vpn/bind_interface_restart_test.dart` | `changed bypass survives a fresh settings widget: true` | Cleared saved consent survives full field unmount and remount. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_restart changed bypass survives a fresh settings widget: true` |
| `test/features/vpn/bind_interface_restart_test.dart` | `saved bypass false wins over the opposite runtime binding` | Absent saved consent, not opposite live binding, controls restored Off state. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_restart saved bypass false wins over the opposite runtime binding` |
| `test/features/vpn/bind_interface_restart_test.dart` | `saved bypass true wins over the opposite runtime binding` | Saved consent, not opposite live binding, controls restored On state. | KEEP; `test/features/vpn/bind_interface_contract_test.dart` / `bind_interface_restart saved bypass true wins over the opposite runtime binding` |
| `test/features/vpn/bypass_adapter_test.dart` | `adapterLabel formats name - ipv4 when an IPv4 is set` | Picker label includes available IPv4. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter adapterLabel formats name - ipv4 when an IPv4 is set` |
| `test/features/vpn/bypass_adapter_test.dart` | `adapterLabel returns just the name when the IPv4 is empty` | Empty address yields bare adapter name. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter adapterLabel returns just the name when the IPv4 is empty` |
| `test/features/vpn/bypass_adapter_test.dart` | `adapterLabel returns just the name when there is no IPv4` | Null address yields bare adapter name. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter adapterLabel returns just the name when there is no IPv4` |
| `test/features/vpn/bypass_adapter_test.dart` | `bypassCandidates drops a NIC with no IPv4` | Adapter without IPv4 is ineligible. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter bypassCandidates drops a NIC with no IPv4` |
| `test/features/vpn/bypass_adapter_test.dart` | `bypassCandidates drops a down NIC` | Down adapter is ineligible for bypass. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter bypassCandidates drops a down NIC` |
| `test/features/vpn/bypass_adapter_test.dart` | `bypassCandidates drops a loopback NIC` | Loopback is ineligible for bypass. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter bypassCandidates drops a loopback NIC` |
| `test/features/vpn/bypass_adapter_test.dart` | `bypassCandidates drops a virtual NIC (tunnel / VM host adapter)` | Virtual/tunnel adapter cannot become bypass. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter bypassCandidates drops a virtual NIC (tunnel / VM host adapter)` |
| `test/features/vpn/bypass_adapter_test.dart` | `bypassCandidates drops an APIPA (169.254.x) NIC` | Link-local DHCP-failure address is excluded despite adapter being up. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter bypassCandidates drops an APIPA (169.254.x) NIC` |
| `test/features/vpn/bypass_adapter_test.dart` | `bypassCandidates keeps a physical up NIC with a routable IPv4` | A usable physical up adapter remains eligible. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter bypassCandidates keeps a physical up NIC with a routable IPv4` |
| `test/features/vpn/bypass_adapter_test.dart` | `bypassCandidates keeps candidates in input order` | Candidate order is stable and determines the default. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter bypassCandidates keeps candidates in input order` |
| `test/features/vpn/bypass_adapter_test.dart` | `defaultBypassAdapter returns an empty string for an empty list` | Empty inventory has no default. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter defaultBypassAdapter returns an empty string for an empty list` |
| `test/features/vpn/bypass_adapter_test.dart` | `defaultBypassAdapter returns an empty string when no candidate exists` | Nonempty but wholly ineligible inventory has no default. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter defaultBypassAdapter returns an empty string when no candidate exists` |
| `test/features/vpn/bypass_adapter_test.dart` | `defaultBypassAdapter returns the first candidate name` | Default selects the first eligible adapter. | KEEP; `test/features/vpn/network_choice_test.dart` / `bypass_adapter defaultBypassAdapter returns the first candidate name` |
| `test/features/vpn/network_choice_prompt_test.dart` | `consent restart failure offers restart retry without saving again` | Restart failure retry invokes restart again without duplicate persistence. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `network_choice_prompt consent restart failure offers restart retry without saving again` |
| `test/features/vpn/network_choice_prompt_test.dart` | `delayed consent prompt respects a choice saved in settings` | Concurrent settings save wins over a delayed prompt read; no stale prompt/write. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `network_choice_prompt delayed consent prompt respects a choice saved in settings` |
| `test/features/vpn/network_choice_remount_test.dart` | `saved restart knowledge survives closing connection settings` | Explicitly retained provider container preserves restart requirement after field remount. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `network_choice_remount saved restart knowledge survives closing connection settings` |
| `test/features/vpn/network_choice_test.dart` | `a prompt waiting on detection returns the latest saved choice` | Delayed VPN detection uses the most recently saved adapter. | KEEP; `test/features/vpn/network_choice_test.dart` / `network_choice a prompt waiting on detection returns the latest saved choice` |
| `test/features/vpn/network_choice_test.dart` | `a saved choice matching automatic still restarts a bound runtime` | Automatic saved choice still restarts a differently bound live runtime without unnecessary save. | KEEP; `test/features/vpn/network_choice_test.dart` / `network_choice a saved choice matching automatic still restarts a bound runtime` |
| `test/features/vpn/network_choice_test.dart` | `applying automatic before inspection still restarts an unknown binding` | Uninspected live binding must restart; persisted bypass is cleared without treating unknown as automatic. | KEEP; `test/features/vpn/network_choice_test.dart` / `network_choice applying automatic before inspection still restarts an unknown binding` |
| `test/features/vpn/network_choice_test.dart` | `old read reports disposal instead of returning stale consent` | Disposed-generation read throws rather than returning or publishing stale consent. | KEEP; `test/features/vpn/network_choice_test.dart` / `network_choice old read reports disposal instead of returning stale consent` |
| `test/features/vpn/network_choice_test.dart` | `old write cannot overwrite rebuilt choice or release its lock: false` | Successful stale-generation write cannot replace rebuilt state or release the replacement lock. | KEEP; `test/features/vpn/network_choice_test.dart` / `network_choice old write cannot overwrite rebuilt choice or release its lock: false` |
| `test/features/vpn/network_choice_test.dart` | `old write cannot overwrite rebuilt choice or release its lock: true` | Failed stale-generation write cannot replace rebuilt state or release the replacement lock. | KEEP; `test/features/vpn/network_choice_test.dart` / `network_choice old write cannot overwrite rebuilt choice or release its lock: true` |
| `test/features/vpn/network_choice_test.dart` | `read started during write cannot replace the saved choice` | Late read cannot overwrite newer saved choice or its restart requirement. | KEEP; `test/features/vpn/network_choice_test.dart` / `network_choice read started during write cannot replace the saved choice` |
| `test/features/vpn/network_choice_test.dart` | `retry after setup save failure keeps choice and avoids another write` | Setup-completion failure is a save error; persisted adapter survives and retry restarts without duplicate consent write. | KEEP; `test/features/vpn/network_choice_test.dart` / `network_choice retry after setup save failure keeps choice and avoids another write` |
| `test/features/vpn/network_choice_test.dart` | `shared write lock lasts through setup completion and restart` | Competing apply is rejected while setup/restart is pending; busy clears after completed restart. | KEEP; `test/features/vpn/network_choice_test.dart` / `network_choice shared write lock lasts through setup completion and restart` |
| `test/features/vpn/network_choice_test.dart` | `successful persistence still attempts restart after container disposal` | A successful in-flight save still attempts restart after its original provider container is disposed. | KEEP; `test/features/vpn/network_choice_test.dart` / `network_choice successful persistence still attempts restart after container disposal` |
| `test/features/vpn/vpn_consent_modal_test.dart` | `Escape declines VPN bypass and never grants consent` | Escape cancellation clears/refuses consent and never invokes accept/restart. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `vpn_consent_modal Escape declines VPN bypass and never grants consent` |
| `test/features/vpn/vpn_consent_modal_test.dart` | `accept failure surfaces the error + returns to asking` | Failed save returns to actionable asking rather than staying in restart state. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `vpn_consent_modal accept failure surfaces the error + returns to asking` |
| `test/features/vpn/vpn_consent_modal_test.dart` | `accept records the suggested adapter + fires onAccept` | Explicit accept persists suggested adapter before invoking completion. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `vpn_consent_modal accept records the suggested adapter + fires onAccept` |
| `test/features/vpn/vpn_consent_modal_test.dart` | `backdrop declines VPN bypass and never grants consent` | Backdrop dismissal clears/refuses consent and never invokes accept/restart. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `vpn_consent_modal backdrop declines VPN bypass and never grants consent` |
| `test/features/vpn/vpn_consent_modal_test.dart` | `close declines VPN bypass and never grants consent` | Close control clears/refuses consent and never invokes accept/restart. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `vpn_consent_modal close declines VPN bypass and never grants consent` |
| `test/features/vpn/vpn_consent_modal_test.dart` | `decline clears the consent + hides the modal` | Explicit decline clears consent and hides the prompt. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `vpn_consent_modal decline clears the consent + hides the modal` |
| `test/features/vpn/vpn_consent_modal_test.dart` | `hides when no VPN owns the default route` | A VPN that does not carry the default route does not prompt. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `vpn_consent_modal hides when no VPN owns the default route` |
| `test/features/vpn/vpn_consent_modal_test.dart` | `hides when no bypass candidate exists` | No eligible bypass adapter suppresses the prompt. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `vpn_consent_modal hides when no bypass candidate exists` |
| `test/features/vpn/vpn_consent_modal_test.dart` | `hides when the user already consented` | Existing saved consent suppresses the prompt. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `vpn_consent_modal hides when the user already consented` |
| `test/features/vpn/vpn_consent_modal_test.dart` | `shows the modal when no consent + VPN owns the default route + a candidate exists` | Prompt requires absent consent, actual VPN default-route ownership and usable physical adapter. | KEEP; `test/features/vpn/vpn_consent_contract_test.dart` / `vpn_consent_modal shows the modal when no consent + VPN owns the default route + a candidate exists` |

## Ordered module checks

The 23-case unit block was source-checked, measured and seed-42 verified before
expanding to binding UI. Binding UI was independently measured and seed-checked
before consent UI; consent was also independently measured and seed-checked.
Module commands select the same normalized cases, but their expanded source argv
change as shown; do not call these identical argv. Each uses default settings.
The separate entire-folder and full-suite comparisons below use identical argv.


### Controller and adapter

```sh
# A: original sources
flutter test --machine test/features/vpn/network_choice_test.dart test/features/vpn/bypass_adapter_test.dart
# B: candidate sources
flutter test --machine test/features/vpn/network_choice_test.dart
```

| Capture | Complete wall s | Child CPU s | File sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| unit-a1 | 8.240 | 14.826 | 10.783 | 10.499 | 0.268 |
| unit-b1 | 8.584 | 11.359 | 5.891 | 5.512 | 0.350 |
| unit-b2 | 9.150 | 12.134 | 6.204 | 5.895 | 0.287 |
| unit-a2 | 9.443 | 14.345 | 12.565 | 12.240 | 0.309 |
| unit-a3 | 10.138 | 14.727 | 13.277 | 12.878 | 0.373 |
| unit-b3 | 9.945 | 13.289 | 6.714 | 6.303 | 0.370 |

wall **9.443 → 9.150 s** (-3.10%); CPU **14.727 → 12.134 s** (-17.61%). Wall favors B in 2/3 pairs; CPU in 3/3.

### Binding field and restart

```sh
# A: original sources
flutter test --machine test/features/vpn/bind_interface_field_test.dart test/features/vpn/bind_interface_restart_test.dart
# B: candidate sources
flutter test --machine test/features/vpn/bind_interface_contract_test.dart
```

| Capture | Complete wall s | Child CPU s | File sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| field-a1 | 14.716 | 22.455 | 20.551 | 13.195 | 7.332 |
| field-b1 | 14.730 | 19.336 | 11.466 | 6.143 | 5.294 |
| field-b2 | 13.167 | 17.424 | 10.150 | 5.188 | 4.932 |
| field-a2 | 13.568 | 25.030 | 20.374 | 12.237 | 8.108 |

wall **14.142 → 13.949 s** (-1.37%); CPU **23.743 → 18.380 s** (-22.59%). Wall favors B in 1/2 pairs; CPU in 2/2.

### Consent, late read and remount

```sh
# A: original sources
flutter test --machine test/features/vpn/vpn_consent_modal_test.dart test/features/vpn/network_choice_prompt_test.dart test/features/vpn/network_choice_remount_test.dart
# B: candidate sources
flutter test --machine test/features/vpn/vpn_consent_contract_test.dart
```

| Capture | Complete wall s | Child CPU s | File sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| consent-a1 | 8.795 | 19.683 | 19.303 | 13.973 | 5.316 |
| consent-b1 | 9.892 | 14.182 | 7.447 | 4.586 | 2.850 |
| consent-b2 | 9.183 | 13.753 | 7.081 | 4.528 | 2.537 |
| consent-a2 | 8.543 | 18.994 | 19.114 | 13.860 | 5.243 |

wall **8.669 → 9.538 s** (+10.02%); CPU **19.338 → 13.967 s** (-27.77%). Wall favors B in 0/2 pairs; CPU in 2/2.

Consent is slower in both isolated wall comparisons (+10.02% median),
despite lower CPU in both. This negative result is retained separately, not pooled
with the positive entire-folder measurement. Binding wall is mixed (one of two
pairs improves). The folder/full observations decide broader elapsed claims.

## Entire VPN folder

Identical command in A/B, B/A, A/B order:

```sh
flutter test --machine test/features/vpn
```

All six captures have exactly the same normalized 55-case outcome Counter,
including multiplicity, result, skip flag and skip reason. Discovery is seven
original / three candidate runners. Final seed 42 also matches all 55.


| Capture | Complete wall s | Child CPU s | File sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| vpn-a1 | 11.952 | 34.268 | 54.296 | 42.537 | 11.707 |
| vpn-b1 | 11.712 | 24.530 | 23.954 | 16.166 | 7.742 |
| vpn-b2 | 12.349 | 25.242 | 23.935 | 15.419 | 8.463 |
| vpn-a2 | 14.821 | 39.237 | 64.336 | 50.093 | 14.184 |
| vpn-a3 | 15.085 | 41.122 | 68.593 | 54.280 | 14.273 |
| vpn-b3 | 10.885 | 21.874 | 21.375 | 14.955 | 6.386 |

wall **14.821 → 11.712 s** (-20.98%); CPU **39.237 → 24.530 s** (-37.48%). Wall favors B in 3/3 pairs; CPU in 3/3.

## Whole-suite comparison

Identical command, A/B/B/A order:

```sh
flutter test --machine
```

Source snapshots restore exact original/candidate bytes and modes. The harness
refuses unrelated source edits and HEAD changes, retains all captures, and restores
the final candidate. Our timed tests, compilers, formatter and analyzer never
overlap. Other agents share the host; no concurrency, environment, native-hook,
cache policy or global timing setting was changed.


| Capture | Complete wall s | Child CPU s | File sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| whole-a1 | 159.727 | 1270.521 | 1219.010 | 492.191 | 724.644 |
| whole-b1 | 146.149 | 1150.163 | 1113.495 | 455.770 | 655.769 |
| whole-b2 | 161.452 | 1222.140 | 1236.122 | 470.426 | 762.887 |
| whole-a2 | 135.191 | 1082.511 | 1030.857 | 440.158 | 588.893 |

wall **147.459 → 153.800 s** (+4.30%); CPU **1176.516 → 1186.151 s** (+0.82%). Wall favors B in 1/2 pairs; CPU in 1/2.

With only two full samples per state, median equals mean. Same-source wall
spreads: A 24.536 s, B 15.302 s; median gap 6.342 s.
All four full Counters match: **1858 passes + the same four skips**. No failure
is discarded or called pre-existing; no baseline-failure worktree is needed.

Selected VPN owner file-span medians: 23.672 → 13.440 s;
the other 213 unchanged owners: 1101.262 → 1161.369 s.
These overlapping sums are neither per-owner CPU nor critical-path wall. Changes
to untouched owners are not isolated from cache, scheduling and shared-host load.
The local measurements and four removed startup owners support this bounded
consolidation; they do not establish a stable whole-suite or CI speedup.

Wall is the full subprocess lifetime, including launcher/hooks and cleanup.
Child CPU is completed descendant user+system time (`RUSAGE_CHILDREN`). File
spans cover loader start through last completion; loading and visible non-skipped
case intervals are separate overlapping sums, not elapsed or exclusive CPU.
Independently calculated medians need not add. No cold-build/hardware guarantee.

## Verification and limits

- All six Git byte/mode copies and controller AST preservation pass independently
  of successful tests. A read-only reviewer audited hooks, bindings, fake stores,
  cancellation, async lifetimes, history and every KEEP row before expansion.
- Six unit, four binding, four consent and six folder captures; seed 42 per block
  and final folder; four full captures. Exact normalized Counters match throughout.
- `flutter analyze`: no issues, covering types/lint and unused imports/elements,
  plus dead-code diagnostics (15.29 s complete command, 13.1 s reported analyzer
  phase). No separate unused-code tool is configured.
- `dart format --output=none --set-exit-if-changed lib test integration_test`,
  `python3 scripts/test-policy.py`, seven existing policy examples and diff checks
  pass; 821 Dart files format with zero changes. The existing configured
  linter/policy is sufficient; no new rule needed.
- Original long test-declaration blocks and the new anonymous group callback
  wrapping the unchanged controller main are an explicit registration-only
  exception to function/nesting limits. Controller registration changes 175→185
  lines. Copied case files are 103/369/67/239/80/47 lines, below the 400-line file
  limit. No new scenario/helper/type or production logic is added; production
  coverage thresholds are unaffected. No new coverage percentage or mutation
  result is claimed.
- Live documentation paths are updated; historical reports keep original paths.
  CI still discovers `*_test.dart`; the existing guard enforces one scoped owner
  per case library. No test, helper or import is orphaned. AGENTS already records
  the contract/value, fixture, ownership and timing policy; no duplicate added.

No production/schema/public API, dependency, generated binding, Moss source, CI,
focus/skip/todo, timeout/retry, real delay or policy-exception change. No Rust,
native/device, live-network, platform integration or real restart tests were run
in this round. The four unchanged native skips and their reasons follow.


- `test/gateway/real_bridge_dispatch_test.dart` / `channel: send lands in the channel runtime` — `native libs not built: mosh-core/target/release/mosh_core.dll / moss-runtime/moss.dll`.

- `test/gateway/real_bridge_dispatch_test.dart` / `dm: send lands in the DM runtime; a missing id answers typed` — `native libs not built: mosh-core/target/release/mosh_core.dll / moss-runtime/moss.dll`.

- `test/gateway/real_bridge_dispatch_test.dart` / `group: send lands in the group runtime; after leave the lookup misses` — `native libs not built: mosh-core/target/release/mosh_core.dll / moss-runtime/moss.dll`.

- `test/gateway/real_bridge_dispatch_test.dart` / `undecodable attachment bytes cross as the typed error on every kind` — `native libs not built: mosh-core/target/release/mosh_core.dll / moss-runtime/moss.dll`.


Future process-global state, HTTP/native access or binding changes can invalidate
worker compatibility; keep such probes independent. Seed 42 does not prove every
ordering. New full test paths gain the ledger prefixes. Run a driver normally or
pass an individual `*_cases.dart` explicitly when debugging one library.

## Changed files

- Six sibling renames in `test/features/vpn/`: `bypass_adapter`,
  `bind_interface_field`, `bind_interface_restart`, `vpn_consent_modal`,
  `network_choice_prompt`, `network_choice_remount`, `*_test.dart` → `*_cases.dart`.
- Scoped imports/registration in existing `network_choice_test.dart`.
- New `bind_interface_contract_test.dart` and `vpn_consent_contract_test.dart`.
- This audit, its `docs/testing.md` pointer, and live references in
  `docs/Features/settings-redesign.md` / `docs/architecture-deepening.plan.md`.

Private snapshots, raw logs, commands, Counters, source proofs and independent
review remain under `.git/test-audit/vpn-next/`. No build artifact is committed.
Nothing is pushed, deployed or published.
