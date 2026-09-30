# ADR 0035: Opt-in crash reporting via Sentry

Date: 2026-09-30
Status: Accepted. Layer 1 (Dart SDK, consent, scrubbing) implemented.

## Context

Release builds had no crash visibility. Dart errors vanished (no
`FlutterError.onError`), and the only record was the local
[field log](../Features/field-log.md). Mosh is a privacy-first messenger with
no server of its own, so any report leaving the device is a new data flow
that users must choose.

## Decision

- **Sentry SaaS** (`redstone-aq/flutter`) through `sentry_flutter`. Reports go
  straight from the client; the DSN is public by design, so no relay.
- **Opt-in, off by default.** One switch in Settings → Privacy. The consent is
  `crash-reporting.json` in the data dir, read by `mosh-core`
  (`crash_reporting.rs`), and holds the install's scrub salt. Opting out stops
  the SDK, deletes the file and the native SDK's queue
  (`<data dir>/sentry-native`), which also resets the installation id.
- **No DSN, no reporting.** The DSN comes from `--dart-define=SENTRY_DSN`
  (repository variable `SENTRY_DSN` in the release workflows). Dev builds and
  forks cannot report.
- **Errors only.** Errors, crashes and release health. No tracing, no
  breadcrumbs, no screenshots or replay, `sendDefaultPii: false`.
- **Scrub before send.** `CrashReportScrubber` runs as `beforeSend` over
  messages, exception values, frame paths and debug-image paths.

## Threat model

Who could read a report: Sentry staff, anyone with access to the Sentry
project, a Sentry breach, a legal request.

| never leaves the device | why |
|---|---|
| invite URIs | a join capability |
| peer, session, group, org ids | reveal who talks to whom; replaced by `sha256(salt:id)[..8]` |
| IP addresses and multiaddrs | location, identity |
| OS user names in paths | real names |
| message text, keys | the product's core promise |

Salted ids let one install's reports correlate without linking back to real
ids; the salt dies with the opt-out, so a later opt-in is a new install.

Sentry's project setting *Prevent Storing of IP Addresses* must stay on: the
ingest request itself carries the client's IP.

## Consequences

- A native crash (segfault in Rust or FFI) is captured by the native SDK
  while reporting is on, and its minidump bypasses `beforeSend`: it carries
  thread stack memory, which can hold fragments of in-memory data. The switch
  subtitle says so.
- Crashes while reporting is off are not recorded for later sending.
- Next layers: Rust `sentry` crate for background-thread panics, debug-symbol
  upload in CI (`SENTRY_AUTH_TOKEN`), a post-crash "send report?" prompt, and a
  manual report with a reviewed `mosh.log`. The field log's context ids must
  be hashed before that last one ships.
