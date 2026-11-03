# First-run viewport fixture audit

Baseline: `c29b77dcde7f3e1ce0ce39af751c2644fb64822a` on
`test/prune-low-value-suites`; clean working tree before this change.
Scope: `test/features/onboarding/first_run_viewports_test.dart` only.
All 18 cases stay. No test, helper or production declaration is deleted.

## Contract and fixture change

Each case mounts the real app at an independently saved onboarding step,
checks Russian action geometry at its viewport/text scale, taps the action,
then checks persisted progression or the sessions route. These protect the
48px/readability regression from `165fab59` (bundled Inter and readable setup
buttons) and the six sizing representatives retained by `93ef2f30`.
Both commits and the implementation were read before changing the fixture.

Previously each case mounted with the default locale, wrote Russian through
`LocaleNotifier.setLocale`, and settled the rebuilt app again. Now the existing
`MemoryLocalePreferenceStore(const Locale('ru'))` is passed to `FirstRunHarness`.
`LocaleNotifier.build` reads this store synchronously, so the first app mount
already uses Russian. Only the unasserted late preference change and its settle
are removed; the original harness, mounting settle, post-tap settle, actual
actions, exceptions, bounds, persistence assertions and preview calls remain.

`SetupStableLayout` resets its natural-height measurement when locale changes.
Starting directly in Russian must therefore be checked against the final
Russian layout, not assumed equivalent from passing inequalities. Temporary
diagnostic variants compare **all 18 exact CTA rectangles**, actual Russian
locale, encoded saved profiles before/after the action and post-action sessions
visibility. All 36 before/after records match exactly. Diagnostic prints are
removed and their runs are excluded from the timing samples.

Do not combine the three starting steps into one flow: the stable layout retains
the initial step's height, so that would change the restored-step contract.
Runtime language switching still has these unchanged callers:

- `test/features/settings/language_settings_test.dart` /
  `manual selection applies immediately, persists, and can return to System`:
  actual choice updates UI and storage; returning to System clears the override.
- `test/features/onboarding/first_run_wizard_test.dart` /
  `$step fits $size with enlarged Russian text`: all three steps at 1200x850
  and 390x844, scale 2, still switch locale after mounting and check usability.
- `test/features/onboarding/first_run_responsive_test.dart` /
  `$step fits the first viewport at $size`: all steps at 1280x680 and 900x700
  still switch locale after mounting and check the first viewport.

## Case ledger

Every row below belongs to
`test/features/onboarding/first_run_viewports_test.dart` (no describe prefix).
The full runtime names identify the cases. Every decision is **REWRITE fixture**:
seed Russian before mounting; preserve the cold starting step and every
assertion. Contract: bounds/48px action plus persisted next step for name/device,
or bounds/48px action plus sessions for network. No DELETE/MERGE decisions.

| Full test path within the file | Protected boundary | Decision |
| --- | --- | --- |
| `SetupStep.name remains usable at Size(320.0, 568.0) with text scale 2.0` | Small portrait, name → device | REWRITE fixture |
| `SetupStep.device remains usable at Size(320.0, 568.0) with text scale 2.0` | Small portrait, device → network | REWRITE fixture |
| `SetupStep.network remains usable at Size(320.0, 568.0) with text scale 2.0` | Small portrait, network → sessions | REWRITE fixture |
| `SetupStep.name remains usable at Size(568.0, 320.0) with text scale 2.0` | Short landscape, name → device | REWRITE fixture |
| `SetupStep.device remains usable at Size(568.0, 320.0) with text scale 2.0` | Short landscape, device → network | REWRITE fixture |
| `SetupStep.network remains usable at Size(568.0, 320.0) with text scale 2.0` | Short landscape, network → sessions | REWRITE fixture |
| `SetupStep.name remains usable at Size(768.0, 1024.0) with text scale 2.0` | Tablet large text, name → device | REWRITE fixture |
| `SetupStep.device remains usable at Size(768.0, 1024.0) with text scale 2.0` | Tablet large text, device → network | REWRITE fixture |
| `SetupStep.network remains usable at Size(768.0, 1024.0) with text scale 2.0` | Tablet large text, network → sessions | REWRITE fixture |
| `SetupStep.name remains usable at Size(800.0, 450.0) with text scale 1.0` | Short desktop, name → device | REWRITE fixture |
| `SetupStep.device remains usable at Size(800.0, 450.0) with text scale 1.0` | Short desktop, device → network | REWRITE fixture |
| `SetupStep.network remains usable at Size(800.0, 450.0) with text scale 1.0` | Short desktop, network → sessions | REWRITE fixture |
| `SetupStep.name remains usable at Size(1920.0, 1080.0) with text scale 2.0` | Desktop large text, name → device | REWRITE fixture |
| `SetupStep.device remains usable at Size(1920.0, 1080.0) with text scale 2.0` | Desktop large text, device → network | REWRITE fixture |
| `SetupStep.network remains usable at Size(1920.0, 1080.0) with text scale 2.0` | Desktop large text, network → sessions | REWRITE fixture |
| `SetupStep.name remains usable at Size(1920.0, 1080.0) with text scale 1.0` | Desktop columns, name → device | REWRITE fixture |
| `SetupStep.device remains usable at Size(1920.0, 1080.0) with text scale 1.0` | Desktop columns, device → network | REWRITE fixture |
| `SetupStep.network remains usable at Size(1920.0, 1080.0) with text scale 1.0` | Desktop columns, network → sessions | REWRITE fixture |

An AST audit reconstructs the original declarations by restoring the original
fixture and two removed preparation statements. All declaration tokens then
match, including matrix dimensions, case names, inputs, actions and assertions.
The only import change replaces the unused locale-provider import with the
existing locale-store helper. This structural and runtime comparison supplies
the fixture-equivalence evidence beyond the green remaining suite.

## Measurements and validation

Commands are unchanged between source snapshots:

```sh
flutter test --machine test/features/onboarding/first_run_viewports_test.dart
flutter test --machine
```

Use the ordinary warm cache, default runner settings and serial invocations.
No own analyzer, diagnostic/compiler or other test command runs alongside a
timed command. The target is byte-checked and restored after A/B source swaps.
Artifact labels and JSON logs are local in `.git/test-audit/viewport-locale/`.
They include the baseline commit, immutable source snapshots and exit status.
No environment, dependency, timeout, animation or CI change is involved.

| Focused pair | Before process wall (s) | After process wall (s) | Execution order |
| --- | ---: | ---: | --- |
| 1 | 15.480 | 13.132 | A/B |
| 2 | 12.952 | 11.837 | B/A |
| 3 | 13.190 | 12.744 | A/B |

| Focused median, 3 samples/state | Before (s) | After (s) |
| --- | ---: | ---: |
| Whole process wall, launcher/hooks included | 13.190 | 12.744 |
| Child CPU | 19.980 | 18.621 |
| Sum of file spans, loading included | 11.222 | 10.814 |
| Loading sum | 4.194 | 4.174 |
| Visible test-body sum | 7.012 | 6.038 |

All three pairs favor the candidate. Median process wall decreases **3.4%**,
CPU **6.8%** and visible body time **13.9%**. All six timed invocations pass
the same 18 cases without skips. This is a modest local reduction; all samples
are retained, including the slower first control.

| Full run, one sample/state | Before (s) | After (s) |
| --- | ---: | ---: |
| Whole process wall, launcher/hooks included | 204.341 | 163.475 |
| Child CPU | 1184.067 | 1174.227 |
| Sum of file spans, loading included | 1560.447 | 1251.297 |
| Loading sum | 644.617 | 520.172 |
| Visible test-body sum | 912.940 | 728.905 |

Both full invocations pass **1921 tests**, discover **268 entry-point files**
and retain the same **4 skips** for missing native DLLs. Exact file/full-name/
result/skip multiplicities and all four skip reasons match. No baseline failure
occurred, and none is used to excuse a failure after the change.

The 40.866s full-wall reduction **cannot be attributed to this fixture change**.
The changed file's full-run span actually grows **10.968 -> 11.404s**, and its
visible body sum grows **8.766 -> 8.976s**. Untouched suites account for 309.586s
of reduced file spans, offset by the 0.436s growth here; this does not establish
the cause of the overall reduction.
Whole-process wall includes launcher/hooks and is distinct from overlapping
file spans: their sum is not elapsed execution time. One full pair demonstrates
successful integration, not dependable overall/CI acceleration. The supported
speed claim is the smaller three-pair focused result above.

Validation:

- AST preservation audit passes after the benchmark source restoration.
- Both 18-case diagnostic variants pass and have identical 36 contract records.
- `flutter analyze`: no issues; includes type, lint and unused-import/declaration
  diagnostics. No separate Dart unused-code check is configured.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  800 files, zero changes.
- `python3 -B scripts/test-policy.py` and all seven policy example tests
  (`python3 -B -m unittest discover -s scripts -p test_test_policy.py`) pass.
- Both full commands pass; the retained settings/wizard/responsive locale-change
  cases run successfully in each. No runner lists or CI gates need updating.
- The final Dart source matches the audited/benchmarked candidate snapshot;
  `git diff --check` passes. No orphaned helper or import remains.

Limits: default Flutter tests use the existing scripted native/disk seams.
The optional `SETUP_PREVIEW` font/screenshot mode, native integration and live
hardware/network runners are not run. Their code and gates stay unchanged.
No production, Rust, generated binding, public API or dependency change is made.

## Recheck at `77131ead`: two further proposals rejected

Baseline `77131eaddd15a9ed5146b7cd98aec9ff57676197`, initially clean.
The current viewport source is `first_run_viewports_cases.dart`, registered by
`first_run_viewport_flow_test.dart` under `first_run_viewports`. All 18 paths in
the original ledger above now have that group prefix; their final decision in
this recheck is **KEEP**. All six sizes/scales and independent saved steps stay.

The proposed 18 → 6 name→device→network flows are rejected before implementation.
`SetupStableLayout` records the first child's natural height and does not reset
it on step changes. `SetupStepTransition` also retains its initial/visited panels,
and the scroll view retains its offset. A reached device/network screen therefore
does not replace its independently restored counterpart. Existing tests at other
sizes do not cover all six original cold-start combinations. The earlier warning
in this audit applies directly; this is not a compiler-only or library-only check.

A narrower trial changed only six callbacks in `first_run_responsive_cases.dart`:
seed the existing Russian locale store instead of mounting English, switching
to Russian and settling again. Each saved starting step and real app mount stayed
independent. AST reconstruction recovered every original declaration token by
restoring only the fixture and two preparation statements; every assertion,
matrix, name, preview call and other callback/helper remained unchanged.

Nevertheless, passive records after the original assertion/preview suffix found
different progress-indicator geometry. Both 27-case diagnostic commands passed,
with identical outcome Counters. No extra scrolling, focus operation or pump was
inserted before observation. Card, viewport, frame, CTA, actual locale, encoded
profile, scroll metrics and focus label matched in all six records; progress
matched only in the two name records. The four mismatches were:

| Size | Starting step | Original progress top | Seeded progress top |
| --- | --- | ---: | ---: |
| 900×700 | device | 120 px | 131 px |
| 900×700 | network | 82 px | 114 px |
| 1280×680 | device | 129 px | 140 px |
| 1280×680 | network | 105 px | 122.02 px |

The seeded locale can establish the stable height during initial provider loading;
the original later locale change resets measurement after loading. A green set
of fit inequalities does not demonstrate equivalent measured layout. The earlier
18-case fixture proof at different dimensions cannot substitute for these records.
The loading/baseline mechanism is inferred from source; the private baseline
field itself was not instrumented.
The trial was rejected and restored byte-for-byte, including file mode. A special
step branch for only two matching records was not added without a measured benefit.

All following full paths are under `test/features/onboarding/first_run_responsive_cases.dart`;
their runtime owner is `test/features/onboarding/first_run_layout_test.dart`.

| Full group/test path | Protected contract | Final decision and evidence |
| --- | --- | --- |
| `first_run_responsive SetupStep.name fits the first viewport at Size(1280.0, 680.0)` | Independently restored Russian name step fits without scrolling | KEEP; record matched, but no partial rewrite or measured saving retained. |
| `first_run_responsive SetupStep.device fits the first viewport at Size(1280.0, 680.0)` | Independently restored Russian device step fits without scrolling | KEEP; proposed fixture moves progress by 11 px. |
| `first_run_responsive SetupStep.network fits the first viewport at Size(1280.0, 680.0)` | Independently restored Russian network step fits without scrolling | KEEP; proposed fixture moves progress by 17.02 px. |
| `first_run_responsive SetupStep.name fits the first viewport at Size(900.0, 700.0)` | Independently restored Russian name step fits without scrolling | KEEP; record matched, but no partial rewrite or measured saving retained. |
| `first_run_responsive SetupStep.device fits the first viewport at Size(900.0, 700.0)` | Independently restored Russian device step fits without scrolling | KEEP; proposed fixture moves progress by 11 px. |
| `first_run_responsive SetupStep.network fits the first viewport at Size(900.0, 700.0)` | Independently restored Russian network step fits without scrolling | KEEP; proposed fixture moves progress by 32 px. |

Reviewed implementation, ADR 0036 and history `165fab59`, `35fd6d56`, `b2a855a9`,
`eb9fa265`, `93ef2f30`, `b743f14a`, `5fa08c58` and the runner move `4998d309`.
No known regression or test is deleted. All six wizard enlarged-Russian runtime
switches, the responsive unsaved-name/resize switch, and the settings manual
language/persistence/System case remain intact. Root owned edits and checks;
one independent reviewer checked source/history, candidate reconstruction and
diagnostic differences without editing tracked files or running a compiler.

Original commands and complete wall / child CPU / overlapping file spans:

| Command | Passed | Wall s | Child CPU s | File sum s |
| --- | ---: | ---: | ---: | ---: |
| `flutter test --machine test/features/onboarding/first_run_viewport_flow_test.dart` | 23 | 16.295 | 24.712 | 14.145 |
| `flutter test --machine test/features/onboarding/first_run_layout_test.dart` | 27 | 12.366 | 18.071 | 10.482 |

Diagnostic original/candidate wall was 14.059/13.152 s, CPU 21.365/20.106 s and
file spans 11.783/10.925 s. These instrumented runs are recorded, not used as a
speed comparison: source equivalence failed and the candidate was discarded.
File sums exclude launcher work and overlap under parallel execution; they are
neither complete wall nor exclusive CPU. Other agents use the same host.

After restoration, seed 42 runs the viewport, layout and entry owners together:
74 passes, zero skips/failures; the Counter exactly matches the three baseline
owners. All test sources, helpers, runners and configuration match baseline Git.
The complete suite therefore remains 1858 passes plus the same four native gates
and 227 runners established by the preceding audit; it is not rerun here because
no test-code change survives. No acceleration is claimed. There is no baseline
test failure; the diagnostic-equivalence rejection is separate from test results.

Final checks pass: `flutter analyze` (no issues, 10.8 s; includes unused-code
diagnostics), format check over 816 files (zero changes), test policy and all seven
policy examples, and `git diff --check`. No new lint rule or test was added.

Raw records, snapshots, commands and independent review are private under
`.git/test-audit/viewport-sequence-next/`. Only this audit and its testing-policy
pointer change. Preview mode, native/device integration and Rust are unrun and
unchanged. The existing policy guards remain sufficient; no dependency, new
abstraction, timeout, sleep, skip, CI or production change is retained.
