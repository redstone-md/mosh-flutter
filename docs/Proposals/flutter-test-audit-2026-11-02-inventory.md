# Small-suite grouping identity inventory

Source: `3943074624ba144e732a458ca112b972f9b89887`. These 92 rows record the
original grouping proposal, verified in its `flutter test --machine` baseline.
The [ordered implementation](flutter-ordered-test-cleanup.md) subsequently
merged two badge cases, grouped all 90 then-current cases and removed three
covered diagnostics cases: 87 remain in these libraries. Current-library links
below follow the renames; original identities and decisions remain historical.
Protected contracts, isolation evidence, risks and checks are in the
[audit](flutter-test-audit-2026-11-02.md#fewer-runners-without-deleting-checks).

Each original library remains separate at its sibling `*_cases.dart` path.
The future runtime map is `(old file, full name N) -> (bounded owner, stem +
" " + N)`, registered exactly once with a scoped group. Owner filenames are
not yet chosen. No assertion, callback or variant may disappear in that trial.
Do not silently combine these unchanged-copy counts with independent MERGE/DELETE
proposals from the audit.

## Diagnostics summaries

4 runners -> 1; 34 cases retained. Honest connection/role/runtime state, DTO-to-summary errors/fallbacks and handwritten equality.

### [channel_group_diagnostics_cases.dart](../../test/features/diagnostics/channel_group_diagnostics_cases.dart)

Original file: `test/features/diagnostics/channel_group_diagnostics_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `channel shows its native details, network and events` |
| `connected group shows its admin role and runtime evidence` |
| `joining member has no invented label, connection or events` |

### [summary_card_cases.dart](../../test/features/diagnostics/summary_card_cases.dart)

Original file: `test/features/diagnostics/summary_card_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `SummaryCard - ready tone renders kicker, title, state, description, and all 3 facts` |
| `SummaryCard - idle tone renders the idle copy + Waiting state + none/paused/none facts` |
| `SummaryCard - error tone renders the Error state badge when an error is present` |
| `RuntimeError renders the alert icon + "Runtime error" label + the message` |

### [diagnostics_sections_cases.dart](../../test/features/diagnostics/diagnostics_sections_cases.dart)

Original file: `test/features/diagnostics/diagnostics_sections_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `DiagnosticsRow renders its label and value` |
| `DiagnosticsGroup renders the uppercased label and its children` |
| `NoActiveSession renders the Session group label + empty-state title + body` |
| `SessionDiagnostics - Conversation details a connected direct session renders all 8 rows` |
| `SessionDiagnostics - Conversation details a relayed session says the network relays it` |
| `SessionDiagnostics - Conversation details a pending session has no path and no peer id yet` |
| `SessionDiagnostics - Conversation details an offline contact reads as offline with its last outcome` |

### [diagnostics_summary_cases.dart](../../test/features/diagnostics/diagnostics_summary_cases.dart)

Original file: `test/features/diagnostics/diagnostics_summary_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `diagnosticsSummary - DM branch ready session with peers -> tone ready, ready-with-peers description` |
| `diagnosticsSummary - DM branch ready session with zero peers -> ready-no-peers description` |
| `diagnosticsSummary - DM branch ready session with null mesh -> ready-no-peers description, booting facts` |
| `diagnosticsSummary - DM branch pending session -> tone waiting, waiting-for-contact copy` |
| `diagnosticsSummary - DM branch handshaking session -> tone waiting, contact-is-offline copy` |
| `diagnosticsSummary - DM branch DM session with error -> tone error overrides state-based tone` |
| `diagnosticsSummary - DM branch title fallback: empty peerDisplayName -> displayName -> Private session` |
| `diagnosticsSummary - idle/error branch no session, no error -> tone idle, idle copy, Waiting state` |
| `diagnosticsSummary - idle/error branch no session WITH error -> tone error, Error state` |
| `helpers peerCount: null mesh -> "booting"` |
| `helpers peerCount: mesh with peerCount=5 -> "5"` |
| `helpers natType: null mesh -> "unknown"` |
| `helpers natType: empty-string natType -> "unknown" (JS \|\| falsy fallback)` |
| `helpers natType: populated natType -> passes through` |
| `helpers relayStatus: relaySessionCount > 0 -> "{n} active"` |
| `helpers relayStatus: relayedPeerCount > 0 (no sessions) -> "{n} relayed"` |
| `helpers relayStatus: relayCapablePeerCount > 0 (no sessions/relayed) -> "{n} capable"` |
| `helpers relayStatus: all zero -> "none"` |
| `DiagnosticSummary value semantics equality + hashCode on equal summaries` |
| `DiagnosticSummary value semantics equality differs when facts differ` |

## Diagnostics network/events

2 runners -> 1; 36 cases retained. Mesh metrics, absent/unknown fields, exact external JSON/time formatting and bounded event rendering.

### [mesh_diagnostics_cases.dart](../../test/features/diagnostics/mesh_diagnostics_cases.dart)

Original file: `test/features/diagnostics/mesh_diagnostics_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `peerBreakdown 2 direct / 3 relayed` |
| `relayBreakdown 1 capable / 4 routes` |
| `MeshDiagnostics - booting null mesh renders the Moss network group + booting empty-state` |
| `MeshDiagnostics - full mesh renders the group label, the 4 metrics, and the 7 rows` |
| `MeshDiagnostics - full mesh supernodeReady false -> "standby" + "not promoted"` |
| `MeshDiagnostics - full mesh empty advertisedAddr -> Advertised row value "-"` |
| `MeshDiagnostics - full mesh empty channels -> Channels row value "-"` |
| `MeshDiagnostics - full mesh MeshDiagnostics - library info (spec #5) renders version, RTT, and the field log path` |
| `MeshDiagnostics - full mesh MeshDiagnostics - library info (spec #5) a null RTT renders the honest unknown` |
| `MeshDiagnostics - full mesh MeshDiagnostics - library info (spec #5) no peer id keeps the RTT row off (channel/group panels)` |
| `MeshDiagnostics - full mesh MeshDiagnostics - library info (spec #5) no library info keeps all the library rows off` |

### [event_log_cases.dart](../../test/features/diagnostics/event_log_cases.dart)

Original file: `test/features/diagnostics/event_log_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `formatTime null epoch -> "-"` |
| `formatTime BigInt.zero -> "-"` |
| `formatTime a fixed epoch -> local HH:mm:ss (deterministic)` |
| `formatTime sub-10 hour/minute/second get zero-padded` |
| `compactDetail empty raw -> ""` |
| `compactDetail empty object -> ""` |
| `compactDetail single-key object -> "foo=bar"` |
| `compactDetail multi-key object -> "a=1 b=2"` |
| `compactDetail nested-object value -> k=JSON.stringify(value)` |
| `compactDetail nested-array value -> k=JSON.stringify(value)` |
| `compactDetail top-level array -> "0=1 1=2" (array-as-object indices)` |
| `compactDetail top-level number -> "42"` |
| `compactDetail whole-valued double renders as int (JS String(42.0) parity)` |
| `compactDetail whole-valued double inside object renders as int` |
| `compactDetail whole-valued double inside array renders as int` |
| `compactDetail genuinely fractional double keeps its fraction` |
| `compactDetail top-level string -> "hi"` |
| `compactDetail top-level true -> "true"` |
| `compactDetail top-level null -> "null"` |
| `compactDetail invalid JSON -> raw fallback` |
| `eventNameColor maps all semantic event-name groups` |
| `eventNameColor keeps unknown event names on the neutral fallback` |
| `EventLog - empty renders the Moss events group label + No-events empty-state` |
| `EventLog - rows 3 events render newest first with time + name` |
| `EventLog - rows 45 events -> only the last 40 render` |

## Conversation inline widgets

3 runners -> 1; 10 cases retained. Badge contrast/type scale/tabular/boundary, typing expiry/kind rules and search caret/prop wiring.

### [unread_badge_cases.dart](../../test/features/conversation/unread_badge_cases.dart)

Original file: `test/features/conversation/unread_badge_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `the count paints with the theme on-accent ink, not white` |
| `the count sits on the labelMedium step` |
| `the count renders with tabular figures` |
| `counts over 99 collapse to 99+` |

### [typing_hint_cases.dart](../../test/features/conversation/typing_hint_cases.dart)

Original file: `test/features/conversation/typing_hint_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `the DM hint names the counterpart while the deadline stands` |
| `an expired DM deadline renders nothing` |
| `the group hint identifies each member typing` |
| `a channel never carries typing: nothing renders` |

### [conversation_search_box_cases.dart](../../test/features/conversation/conversation_search_box_cases.dart)

Original file: `test/features/conversation/conversation_search_box_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `a rebuild with an unchanged query leaves the caret alone` |
| `an externally cleared query still reaches the field` |

## Fingerprint contracts (secondary)

2 runners -> 1; 8 cases retained. Independent literal security vectors and the actual encryption fingerprint dialog.

### [fingerprint_emoji_cases.dart](../../test/features/fingerprint/fingerprint_emoji_cases.dart)

Original file: `test/features/fingerprint/fingerprint_emoji_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `empty fingerprint renders no emoji` |
| `known vector: hex bytes map to their pool slots` |
| `known vector: non-hex seed strings fall back to code units` |
| `a one-byte change moves the quartet` |
| `an odd-length single char falls back to code units and wraps` |
| `hex letter case does not change the mapping` |

### [fingerprint_lock_cases.dart](../../test/features/fingerprint/fingerprint_lock_cases.dart)

Original file: `test/features/fingerprint/fingerprint_lock_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `empty fingerprint renders no lock` |
| `tapping the lock opens the dialog with emoji, hex, hint` |

## Linked-device list (secondary)

2 runners -> 1; 4 cases retained. Readable device identities, own-device removal gate, named confirmation and pending/applied revocation.

### [device_list_cases.dart](../../test/features/device_link/device_list_cases.dart)

Original file: `test/features/device_link/device_list_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `long ids read as head…tail, never wrapped mid-id` |

### [device_revocation_cases.dart](../../test/features/device_link/device_revocation_cases.dart)

Original file: `test/features/device_link/device_revocation_test.dart`. Decision for every row: **KEEP/MOVE unchanged**.

| Full describe/test path |
| --- |
| `only another device offers removal and requires a named confirmation` |
| `shows persisted DeviceRevocationState.pending removal status` |
| `shows persisted DeviceRevocationState.applied removal status` |
