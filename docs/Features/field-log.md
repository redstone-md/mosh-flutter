# Field log

Feature doc for the field log (spec #4): the one plain file the core
writes its operating events to, so a release Windows build — no console,
stderr lost — still leaves an answer to "what happened". Reference:
[Architecture](../Architecture.md).

The file stays on the device: opt-in crash reporting
([ADR 0035](../ADR/0035-opt-in-crash-reporting.md)) does not send it. Its
context ids are raw peer, session and group ids, so they must be hashed
before any report attaches it. The user can share it themselves: see
[Sharing the log](#sharing-the-log).

## The flow

```mermaid
flowchart LR
    A["any runtime call site"] -- "dlog::write" --> S["process sink<br/>static, mutex"]
    S -- "one structured line" --> F["data dir / logs / mosh.log"]
    F -- "grows past 2 MB" --> R["rotate: .1 then .2<br/>oldest dropped"]
    S -. "debug builds only" .-> E["stderr mirror"]
    P["panel: Field log row"] -- "current_log_path()" --> F
```

## The shape of a line

One event, one line, five fields:

```
2026-09-20T14:03:02Z warn verify session-1 dropping unverifiable typing hint
```

`timestamp level kind context message` — UTC ISO-8601 to the second,
lowercase level, a slug from the kind vocabulary, the conversation or
call-site id, and the message. Newlines inside messages are flattened:
one event stays one line, so the file is greppable.

## The kinds vocabulary

Call sites pick from `diagnostics_log::kinds` instead of inventing
spellings; one vocabulary keeps the file filterable. The slugs so far:

`rehydrate` `persist` `identity` `publish` `verify` `offer` `room`
`frame` `connect` `announce` `outbox` `handshake` `delivery` `resend`
`call` `commit` `kick` `resync` `voice` `stream` `panic` `startup` `test`

The `startup` kind carries what kept the app from coming up: the shared
resources (Moss, the data dir, the encrypted store) or a runtime that did
not build, once per process each, and a setup check on the first-run gate
that failed or did not answer in 20 seconds. These, and a connected call
whose microphone captures nothing or whose peer sends no audio for 10
seconds (`call` kind), go through `dlog::report_failure`: an `error` line,
plus a crash report while the user has opted in.

The `stream` kind carries the attachment chunk carrier (spec #8): the
room-wire fallback note and frames that arrive on the reserved inbox
channel but do not deframe.

A DM session's Connect timeline reads from four lines under its session
id: `connect connect_peer requested for <moss id>` (moss was asked to
dial the counterpart, once per device in a linked DM), `connect peer reach <old> -> <new>` (the path to the
counterpart appeared or changed between `None`, `Direct` and `Relayed`),
`handshake session connected (was …)` and `handshake session lost: no
authenticated frame for <ms> (reach …)`, the change back to Handshaking.
Each is written on the change, never per tick. The path is read from one
mesh report per tick, and a tick whose report failed logs no path change;
the proof is
`private_dm_runtime/field_log_tests.rs`.

The `panic` kind carries Rust panics mirrored by the process panic hook
(installed from the first Rust entry point): one `error` line per panic
with its source location, before the default hook runs. It is the only
evidence a release build leaves when a panic on a foreign thread aborts
the process.

On iOS nothing keeps a process's stderr, where Moss's Go runtime prints
why it aborts. Once the data directory is known, stderr goes to
`logs/crash-output.log`. The next launch moves that file to
`crash-output.prev.log`, which is exported with the log. If the file
holds a fatal error or a panic, that line goes into a `startup` error
line and, with consent, a crash report.

## Repeating lines

A retry loop that fails the same way on every turn would push everything
else out of the file. Such call sites write through
`dlog::write_repeating`: the same level, kind, context and message is
written once per five minutes, and the next copy written ends with
`(repeated N more times)`. Up to 256 lines are tracked at once; past
that, a new line is written as is rather than lost. The group runtime's
per-turn warnings (inbound frames dropped, history, admission, deletion
and name sync deferred, history requests it cannot answer) use it.

## Rotation policy

- The live file is `<data dir>/logs/mosh.log`; a write that would push
  it past 2 MB rolls it: `mosh.log` → `mosh.log.1` → `mosh.log.2`, and
  the previous `.2` is dropped. Two rotated copies, freshest first.
- Renames run with the file closed, so rotation works on Windows where
  an open handle cannot be renamed.
- Call sites never decide path or rotation policy; the sink owns both.

## Failure contract

The log must never break the app. Every filesystem failure (a directory
that cannot be created, a file that cannot be opened, a write that
fails) is silently ignored and the next line retries; a poisoned lock is
recovered, not honored. Debug builds mirror each line to stderr, so a
developer run still sees the old console output.

## current_log_path

`dlog::current_log_path()` answers the live file's path once a write has
opened it — `None` before the first write or while the file could not be
created, so the app offers the file only when it exists. The panel's
Field log row shows it, so a bug report can be pointed at the exact
file.

## Sharing the log

Settings → About and the failed-launch screen offer "Share app log".
`log_files()` lists the files that exist; the app joins them oldest first
into one `mosh-log.txt` in the temp dir and hands it to the system share
sheet (`share_plus`). The user decides whether and where the file goes.
Linux has no file sharing there, so the file opens in the text editor.

## Proof

Unit tests in `mosh-core/src/diagnostics_log.rs` (the `diagnostics_log`
test filter):

- `writes_one_structured_line_per_event` — the five-field line shape,
  the empty-context case.
- `rotates_and_keeps_every_line_across_three_files` — nothing dropped
  until the second rotation, oldest lands in `.2`, the size cap holds.
- `reopens_and_appends_across_instances` and
  `a_full_file_rotates_on_reopen` — the sink is per-process state, and a
  full file rotates even across a restart.
- `never_panics_when_the_log_file_cannot_be_created` — the failure
  contract: an occupied file path reports no path and drops lines.
- `the_global_sink_reports_the_resolved_path` — `current_log_path`
  agrees with the resolved data dir.
- `diagnostics_log/repeats.rs` — a repeating line is written once per
  window with its held-back count, each line has its own window, and a
  full table still writes new lines.
- The panel path is pinned in `api/diagnostics.rs`
  (`moss_library_info_reports_the_loaded_library`): the first
  `moss_library_info` call files the library version under the
  `identity` kind with the `moss_library_info` context, so a bug report
  carries what was running.
