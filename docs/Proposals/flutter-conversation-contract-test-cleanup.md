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
