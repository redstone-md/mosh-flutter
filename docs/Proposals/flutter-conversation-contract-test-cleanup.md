# Conversation contracts: fewer full-screen mounts

Starting commit: `4998d309`, initially clean. No production behavior, dependencies,
native/platform gates, clocks, retries or timeouts change in this portion.

## Retry matrix

Read `ConversationSnapshot`, `ConversationMessageRow`, `FailedMessageRetry`,
`conversationSnapshotProvider`, introduction `322a4b5a` and ADR 0018. All three
kinds use one row retry gate (`message.canRetry`) and one renderer, without a
kind-specific retry-visibility branch. The native snapshot mappers do differ,
so their field forwarding must remain protected independently of rendering.

Before removing any screen scenario, strengthen the five existing
`conversation_models_test.dart / conversation_snapshot / canRetry` tests to
read actual generated DM/channel/group snapshots through the production provider.
Each loops all three kinds. Check body, own, deliveryStatus, deliveryError,
retryable and messageId before the predicate. The positive case covers both raw
whitespace error and null error. Other ownership/fingerprint and mapper cases
are unchanged. These are runtime mapping contracts, not compiler guarantees.

Then exercise all six display conditions on the real `ConversationMessageRow`
under its existing component fixture. Keep the three full-screen
`<DM|channel|group>: tapping Retry sends that message again` callbacks unchanged,
including no call before tap and exact Gateway target/messageId after tap. Their
narrowed `_failed` factory supplies exactly the former default field values.

The stronger mapper and row suites passed while all 21 original screen tests
were still present. Only then were the 18 repeated screen registrations removed.
An independent read-only reviewer checked this decomposition against source and
history. Acceptance rests on the actual common gate and preserved mapping/wiring,
not on the number of reviewer approvals or on green remaining tests alone.

All screen rows below are in
`test/features/conversation/conversation_message_retry_test.dart`. Each replacement
is in `test/features/conversation/conversation_message_row_test.dart`; the same
condition also traverses real DTO mapping for all three kinds in the five
strengthened model tests. The old ID `m5` and new `m1` in the counterpart component
fixture are both non-null; neither ID value nor its timestamp participates in
that gate. The dispatch test retains `m-retry-1` exactly.

| Full old test path | Protected contract | Decision / retained component path |
| --- | --- | --- |
| `DM: an own failed message that can be sent again shows the error and Retry` | Mapped body/error/flags plus trimmed error and Retry | REWRITE into `Retry an own failed retryable message shows the trimmed error` plus DTO mapping |
| `DM: with no error text it falls back to "Failed to send"` | Null error survives all three mappers; shared fallback text and Retry | REWRITE into `Retry missing error text falls back to Failed to send` plus DTO mapping |
| `DM: a message that did not fail shows no Retry` | Non-failed status cannot expose Retry | REWRITE into `Retry a message that did not fail shows no Retry` plus DTO mapping |
| `DM: a failure the runtime will not retry shows no Retry` | Runtime refusal hides error and Retry | REWRITE into `Retry a failure the runtime will not retry shows no Retry` plus DTO mapping |
| `DM: a failed message with no id shows no Retry` | Missing native message id cannot expose Retry | REWRITE into `Retry a failed message with no id shows no Retry` plus DTO mapping |
| `DM: someone else's failed message shows no Retry` | Only locally owned messages can expose Retry | REWRITE into `Retry someone else's failed message shows no Retry` plus DTO mapping |
| `channel: an own failed message that can be sent again shows the error and Retry` | Mapped body/error/flags plus trimmed error and Retry | REWRITE into `Retry an own failed retryable message shows the trimmed error` plus DTO mapping |
| `channel: with no error text it falls back to "Failed to send"` | Null error survives all three mappers; shared fallback text and Retry | REWRITE into `Retry missing error text falls back to Failed to send` plus DTO mapping |
| `channel: a message that did not fail shows no Retry` | Non-failed status cannot expose Retry | REWRITE into `Retry a message that did not fail shows no Retry` plus DTO mapping |
| `channel: a failure the runtime will not retry shows no Retry` | Runtime refusal hides error and Retry | REWRITE into `Retry a failure the runtime will not retry shows no Retry` plus DTO mapping |
| `channel: a failed message with no id shows no Retry` | Missing native message id cannot expose Retry | REWRITE into `Retry a failed message with no id shows no Retry` plus DTO mapping |
| `channel: someone else's failed message shows no Retry` | Only locally owned messages can expose Retry | REWRITE into `Retry someone else's failed message shows no Retry` plus DTO mapping |
| `group: an own failed message that can be sent again shows the error and Retry` | Mapped body/error/flags plus trimmed error and Retry | REWRITE into `Retry an own failed retryable message shows the trimmed error` plus DTO mapping |
| `group: with no error text it falls back to "Failed to send"` | Null error survives all three mappers; shared fallback text and Retry | REWRITE into `Retry missing error text falls back to Failed to send` plus DTO mapping |
| `group: a message that did not fail shows no Retry` | Non-failed status cannot expose Retry | REWRITE into `Retry a message that did not fail shows no Retry` plus DTO mapping |
| `group: a failure the runtime will not retry shows no Retry` | Runtime refusal hides error and Retry | REWRITE into `Retry a failure the runtime will not retry shows no Retry` plus DTO mapping |
| `group: a failed message with no id shows no Retry` | Missing native message id cannot expose Retry | REWRITE into `Retry a failed message with no id shows no Retry` plus DTO mapping |
| `group: someone else's failed message shows no Retry` | Only locally owned messages can expose Retry | REWRITE into `Retry someone else's failed message shows no Retry` plus DTO mapping |
| `DM: tapping Retry sends that message again` | Native target/id dispatch from actual screen | KEEP callback and fixture values |
| `channel: tapping Retry sends that message again` | Native target/id dispatch from actual screen | KEEP callback and fixture values |
| `group: tapping Retry sends that message again` | Native target/id dispatch from actual screen | KEEP callback and fixture values |

### Checks and measured scope

Command in both states:

```sh
flutter test --machine test/features/conversation/conversation_models_test.dart test/features/conversation/conversation_message_row_test.dart test/features/conversation/conversation_message_retry_test.dart
```

Three warm pairs, A/B, B/A, A/B. Every control passes 72; every candidate passes
60. Exact runtime name/result/skip Counters differ only by the 18 named screen
paths and six named row paths. The five model test names stay intact while their
callbacks become stronger. The retry widget subset becomes 3 screen + 6 row
cases instead of 21 screen cases; no boundary or failure class is discarded.

| Median observation, seconds | Before | After |
| --- | ---: | ---: |
| Full command wall, including launcher/hooks | 11.947 | 9.889 |
| Completed-child CPU | 21.575 | 18.515 |
| Sum of file spans | 21.223 | 19.092 |
| Sum of loading spans | 14.178 | 14.537 |
| Sum of visible case bodies | 6.518 | 4.283 |

Observed scope wall is **17.2% lower**, CPU **14.2% lower**. These are module
measurements on a shared server, not a whole-suite speedup claim. File spans
and bodies overlap across workers and are neither process wall nor CPU.

- Random order seed 42 passes all 60.
- Analyzer AST audit confirms the retained dispatch callback, original row
  callbacks/helpers and unrelated mapper callbacks remain unchanged. It also
  resolves old factory defaults against the retained dispatch fixture and
  verifies exactly six leaf additions/five mapper rewrites.
- Flutter analysis (including existing unused-code checks), formatting and the
  existing test policy pass. No new test abstraction or timing exception.
- The initial full baseline is 1921 passes, the same four native-library skips,
  zero errors; 256 entry points, 147.939s wall, 1202.088s child CPU. Whole-pipeline
  measurements after the remaining portions will be recorded separately.

Raw sources, commands, AST audit, exact runtime identity deltas and measurements
are in `.git/test-audit/conversation-next/`. Shared-server builds remain an
uncontrolled source of wall/CPU variance; no hardware/concurrency tuning or
external publication is part of this work. Native/platform integration was not
run, and its existing gates remain explicit.

## Keyboard, send and call-history UI reduction

This portion uses intermediate commit `92fdae51` as its unchanged retry baseline;
retry model/row/dispatch edits above are held constant in every UI comparison.
The five original UI sources themselves match the `4998d309` snapshots. Only
those sources are in this scope: keyboard send, send, standalone call history,
DM call-history row and header layout. No production, fixture infrastructure,
clock, timeout, retry, platform gate or dependency is changed.

### Source evidence, independently of passing tests

- **Send:** failure and successful-retry callbacks have identical four-statement
  setup/trigger prefixes. Transfer all five initial body/target/error/Retry/draft
  assertions before Retry in the retained callback, then retain every original
  retry statement and all four postconditions. The two other callbacks, imports
  and helpers are unchanged. Twelve `expect` calls per kind remain twelve;
  three duplicate registrations disappear (12 -> 9).
- **Keyboard:** change only the enum import and the Enter variant selector.
  The callback tokens are unchanged. DM retains Android, iOS, Linux, macOS and
  Windows; channel/group retain Windows. Thus every platform branch of the shared
  composer and every kind's screen wiring remain covered without multiplying
  both axes. No Enter/focus implementation branch combines kind with platform.
  All six identical-new-draft / earlier-failure callbacks and their default
  variants are unchanged. This preserves the `b743f14a` #48/#45 regression rather
  than replacing its widget-owned draft/focus behavior with provider assertions.
- **Header:** the new click callback is exactly the original static-layout
  callback followed by the original click callback with its duplicate fixture
  call removed. Every order/40×40 assertion runs in the same initial state,
  before interaction. Fixture/imports, keyboard-details and separate fingerprint
  action callbacks are unchanged; see introduction `ba77a7fa`.
- **Call history:** inspect the actual `ConversationMessageRow._trailing`, which
  constructs `CallLogEntry(event: callEvent, outgoing: message.own, l: l)`.
  Retain missed incoming label/icon and wrong-icon absence, missed outgoing
  No answer, completed incoming/outgoing direction, and the absent-event case.
  The missed-outgoing and absent-event callbacks and the row fixture are unchanged.
  The original zero-suffix negative is scoped to the actual pill, matching the
  subject of the standalone fixture rather than unrelated row metadata.
- The UI duration branch is only empty/nonempty formatted duration; direction
  and outcome do not branch on its numeric value. Exercise zero and `65000 ->
  1:05` in both directions. Move every original `0/999/1000/65000/3661000`
  formatter assertion unchanged, adding `86000 -> 1:26` for the former row value.
  Specific `1:26` UI instances are represented at the formatter level, not
  falsely described as byte-identical UI assertions. Middle-dot regression
  `b5d09309` and direction/outcome regression `8beb2bef` remain protected;
  introduction `12af4dde` was also read.

A read-only token/source audit confirms these equalities, checks the original
snapshot hashes, and verifies the only keyboard diff is import/variant selection.
It runs no Dart compiler and edits no test sources. This is source evidence in
addition to runtime Counters; a green remaining suite alone is not the deletion
justification. The obsolete standalone call runner and its private-only helpers
can therefore disappear without losing a distinct behavior/error class.

### Full runtime-path ledger

All names are top-level runtime names. Seventeen old full paths disappear and
one formatter path moves into the retained row runner: **46 - 17 + 1 = 30**.
The final row below explicitly records that moved destination; it is not a test
that merely confirms another test was removed.

| Full original/runtime path | Protected contract | Decision / exact retained scenario |
| --- | --- | --- |
| `test/features/conversation/call_log_entry_test.dart` / `a non-zero duration appends · m:ss with zero-padded seconds` | Incoming/outgoing icons and labels at zero and 65000 ms; exact spaced middle dot and padded 1:05. | MERGE into `test/features/conversation/dm_message_row_call_event_test.dart` / `completed incoming and outgoing calls show their direction` |
| `test/features/conversation/call_log_entry_test.dart` / `a zero duration omits the duration suffix` | Incoming missed label/icon, no incoming-completed icon and no middle-dot suffix on the actual pill. | MERGE into `test/features/conversation/dm_message_row_call_event_test.dart` / `a message with a call event shows the call pill` |
| `test/features/conversation/call_log_entry_test.dart` / `completed call renders the phone icon + Incoming call label` | Incoming/outgoing icons and labels at zero and 65000 ms; exact spaced middle dot and padded 1:05. | MERGE into `test/features/conversation/dm_message_row_call_event_test.dart` / `completed incoming and outgoing calls show their direction` |
| `test/features/conversation/call_log_entry_test.dart` / `formatCallDuration renders duration text` | All original formatter boundaries remain; old 86000 ms UI value is additionally checked as 1:26. | MOVE into `test/features/conversation/dm_message_row_call_event_test.dart` / `formatCallDuration renders duration text` |
| `test/features/conversation/call_log_entry_test.dart` / `missed call renders the phone-off icon + Missed call label` | Incoming missed label/icon, no incoming-completed icon and no middle-dot suffix on the actual pill. | MERGE into `test/features/conversation/dm_message_row_call_event_test.dart` / `a message with a call event shows the call pill` |
| `test/features/conversation/conversation_header_layout_test.dart` / `header actions follow call, search, menu with equal hit targets` | Same initial fixture, call/search/menu order and every 40×40 hit target. | MERGE into `test/features/conversation/conversation_header_layout_test.dart` / `clicking the chat name opens details` before the click |
| `test/features/conversation/conversation_keyboard_send_test.dart` / `channel: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.android)` | Shared Enter/focus/admission checks remain on this platform and this kind; no kind × platform code branch. | MERGE matrix into `test/features/conversation/conversation_keyboard_send_test.dart` / `DM: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.android)` and `test/features/conversation/conversation_keyboard_send_test.dart` / `channel: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.windows)` |
| `test/features/conversation/conversation_keyboard_send_test.dart` / `channel: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.iOS)` | Shared Enter/focus/admission checks remain on this platform and this kind; no kind × platform code branch. | MERGE matrix into `test/features/conversation/conversation_keyboard_send_test.dart` / `DM: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.iOS)` and `test/features/conversation/conversation_keyboard_send_test.dart` / `channel: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.windows)` |
| `test/features/conversation/conversation_keyboard_send_test.dart` / `channel: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.linux)` | Shared Enter/focus/admission checks remain on this platform and this kind; no kind × platform code branch. | MERGE matrix into `test/features/conversation/conversation_keyboard_send_test.dart` / `DM: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.linux)` and `test/features/conversation/conversation_keyboard_send_test.dart` / `channel: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.windows)` |
| `test/features/conversation/conversation_keyboard_send_test.dart` / `channel: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.macOS)` | Shared Enter/focus/admission checks remain on this platform and this kind; no kind × platform code branch. | MERGE matrix into `test/features/conversation/conversation_keyboard_send_test.dart` / `DM: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.macOS)` and `test/features/conversation/conversation_keyboard_send_test.dart` / `channel: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.windows)` |
| `test/features/conversation/conversation_keyboard_send_test.dart` / `group: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.android)` | Shared Enter/focus/admission checks remain on this platform and this kind; no kind × platform code branch. | MERGE matrix into `test/features/conversation/conversation_keyboard_send_test.dart` / `DM: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.android)` and `test/features/conversation/conversation_keyboard_send_test.dart` / `group: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.windows)` |
| `test/features/conversation/conversation_keyboard_send_test.dart` / `group: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.iOS)` | Shared Enter/focus/admission checks remain on this platform and this kind; no kind × platform code branch. | MERGE matrix into `test/features/conversation/conversation_keyboard_send_test.dart` / `DM: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.iOS)` and `test/features/conversation/conversation_keyboard_send_test.dart` / `group: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.windows)` |
| `test/features/conversation/conversation_keyboard_send_test.dart` / `group: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.linux)` | Shared Enter/focus/admission checks remain on this platform and this kind; no kind × platform code branch. | MERGE matrix into `test/features/conversation/conversation_keyboard_send_test.dart` / `DM: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.linux)` and `test/features/conversation/conversation_keyboard_send_test.dart` / `group: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.windows)` |
| `test/features/conversation/conversation_keyboard_send_test.dart` / `group: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.macOS)` | Shared Enter/focus/admission checks remain on this platform and this kind; no kind × platform code branch. | MERGE matrix into `test/features/conversation/conversation_keyboard_send_test.dart` / `DM: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.macOS)` and `test/features/conversation/conversation_keyboard_send_test.dart` / `group: Enter keeps focus and admits consecutive sends (variant: TargetPlatform.windows)` |
| `test/features/conversation/conversation_send_test.dart` / `DM: a send that throws keeps the text and shows Retry` | Same initial failure; retain all five body/target/error/Retry/draft assertions and later retry assertions. | MERGE into `test/features/conversation/conversation_send_test.dart` / `DM: a successful retry clears the banner and the composer` before its Retry action |
| `test/features/conversation/conversation_send_test.dart` / `channel: a send that throws keeps the text and shows Retry` | Same initial failure; retain all five body/target/error/Retry/draft assertions and later retry assertions. | MERGE into `test/features/conversation/conversation_send_test.dart` / `channel: a successful retry clears the banner and the composer` before its Retry action |
| `test/features/conversation/conversation_send_test.dart` / `group: a send that throws keeps the text and shows Retry` | Same initial failure; retain all five body/target/error/Retry/draft assertions and later retry assertions. | MERGE into `test/features/conversation/conversation_send_test.dart` / `group: a successful retry clears the banner and the composer` before its Retry action |
| `test/features/conversation/dm_message_row_call_event_test.dart` / `formatCallDuration renders duration text` | Same formatter contract, with all old boundaries and the old row duration. | MOVE destination from `test/features/conversation/call_log_entry_test.dart` / `formatCallDuration renders duration text` |

### Targeted and folder measurements

The private target dispatcher executes `flutter test --machine` with the five
named source paths before and four afterward, omitting only the removed call
runner; every actual command is recorded. Two pairs run A/B, then B/A. Both
controls pass 46, both candidates pass 30, with no skips/errors. Entry points
are **5 -> 4**, so only one worker is removed. Registrations are not mounts:
source fixture-pump calls are 46 -> 32 (keyboard 21 -> 13, send 12 -> 9,
call/header 13 -> 10). The completed-call row case pumps four variants afterward
versus two before; no claim of 46 -> 30 mounts is made.

| Targeted median observation, seconds | Before | After |
| --- | ---: | ---: |
| Full command wall, launcher/hooks included | 11.878 | 10.146 |
| Completed-child CPU | 32.657 | 26.523 |
| Sum of file spans | 36.565 | 27.807 |
| Sum of loading spans | 21.850 | 16.595 |
| Sum of visible case bodies | 14.684 | 11.194 |

Observed target wall is **14.6% lower**, CPU **18.8% lower**. Raw wall pairs
are 12.113 / 10.206, then 10.087 / 11.644 (B/A); corresponding CPU
values are 33.452 / 26.426, then 26.620 / 31.862.

The broader identical command, `flutter test --machine
test/features/conversation`, is deliberately reported separately. It passes
590 -> 574 with no skips/errors and has 71 -> 70 entry points. Runtime identity
Counters for both target and folder comparisons differ by exactly the same 17
old paths and one formatter destination, including duplicate multiplicity.

| Conversation-folder median observation, seconds | Before | After |
| --- | ---: | ---: |
| Full command wall, launcher/hooks included | 47.656 | 48.473 |
| Completed-child CPU | 343.827 | 351.181 |
| Sum of file spans | 322.876 | 328.624 |
| Sum of loading spans | 132.085 | 133.739 |
| Sum of visible case bodies | 190.242 | 194.318 |

Folder wall samples are 50.314 -> 53.400 and, in reverse order,
43.545 -> 44.998. CPU samples are 362.443 -> 389.642 and
312.720 -> 325.211. Their inconsistent directions on the shared server are
**noisy/inconclusive**; neither a folder regression nor whole-suite speedup is
established. The targeted reduction does not predict full pipeline savings.
File/loading/body sums overlap across parallel workers and are neither elapsed
wall nor CPU. Whole-pipeline observations are recorded separately.

The reviewed snapshots, 32 source/token checks, full runtime identity deltas and
parsed measurements are in `.git/test-audit/conversation-next/ui-audit/`; inputs
are immutable `baseline/`, `ui-candidate/`, `ui-target-{before,after}-{1,2}` and
`ui-{before,after}-{1,2}` records. No tests/compiler/analyzer were launched by
this independent audit, and no measured sample was discarded for its direction.
