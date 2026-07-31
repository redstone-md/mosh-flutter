# Flutter fork glossary

Companion to the existing `CONTEXT.md` ubiquitous language. This file only
records terms introduced by the Flutter-rewrite effort (ADRs 0009-0011). All
domain terms (org, roster, moss peer-id, MLS fingerprint, confirmation code,
etc.) remain defined in `CONTEXT.md` and are not redefined here.

## Flutter fork

## Slice (Flutter fork sense)

A vertical slice of the rewrite. Slice one = onboarding + invite paste +
fingerprint confirm + one DM screen + diagnostics, built over the bridge
with the temporary fake gateway (ADR 0013). Later slices add deep-link
association, mobile builds, and the remaining screens.

## Deep-link association

OS-level registration of the `mosh://` scheme so opening an invite URI
launches the app and pre-fills the invite field. Planned as a later slice,
NOT in slice one (ADR 0015). Slice one supports only manual paste.

## Temporary fake gateway

An in-Dart implementation of the `mosh_core::api` surface used only in slice
one so widget tests run without the Rust runtime. Gated behind an interface
and a single provider; removed or kept flagged before slice one closes.
Explicit exception under `AGENTS.md` exception_policy (ADR 0013).

## LocaleProvider

A Riverpod provider holding the active `Locale`, laid in slice one so a
manual language switch can be added later as one widget. Slice one resolves
locale from the device by default (ADR 0014).

## gen-l10n

Flutter's framework-blessed localization generator. Reads ARB files under
`lib/l10n`, produces `AppLocalizations`. The fork seeds `app_en.arb`
(template) and `app_ru.arb` from slice one (ADR 0014).

## Wire frame (voice call)

The binary voice-call frame layout `[seq:u64 BE][ciphertext-with-tag]` with
AES-GCM nonce = `[nonce_prefix(4)][seq(8)]` and a direction bit in seq. In
the Flutter fork this lives in `mosh-core` only, never in Dart, so there is
one source of truth (ADR 0012).

## 0.8.0-dev

The fork's version line, separate from upstream `mosh` 0.7.x. Makes the
post-Tauri line visible; upstream takes it as a minor on merge (ADR 0015).

The sandboxed fork of `mosh` where the Tauri + React frontend is replaced by a
Flutter + Dart frontend. Lives until the rewrite proves out and is merged
back upstream. Distinct from the upstream Tauri branch, which keeps living.

## mosh-core

The Tauri-free Rust crate that owns crypto, transport, persistence, and
runtimes. Already platform-agnostic (no `tauri`/`webview` references). In the
Flutter fork it is linked into the Dart app through `flutter_rust_bridge`
instead of being driven by a Tauri shell. Not rewritten.

## api module (`mosh_core::api`)

The thin Rust facade over the runtimes that `flutter_rust_bridge` binds. Each
function in `api` corresponds to one current Tauri command; each `api`
function returning `StreamSink<T>` corresponds to one current Tauri event.
The only Rust surface the bridge sees. (Proposed in ADR 0010.)

## FFI bridge

The generated, typed Dart-Rust bridge produced by `flutter_rust_bridge` from
the `api` module. Replaces both the Tauri command calls and Tauri event
listen calls of the old frontend. (Proposed in ADR 0010.)

## Server state (Flutter fork sense)

Runtime / async state coming from `mosh-core` through the bridge: session
snapshots, message lists, diagnostics, delivery status. Modeled with
Riverpod `AsyncNotifierProvider` as `AsyncValue<T>` (loading/data/error).
Direct analogue of TanStack Query server state. (Proposed in ADR 0010.)

## UI state (Flutter fork sense)

Ephemeral widget-local state: open drawer, selected session, composer draft,
modal visibility, animation controllers. Lives in `StatefulWidget` state or
`flutter_hooks`, never in Riverpod providers. Direct analogue of Zustand
granular stores vs local React state. (Proposed in ADR 0010.)

## Secure storage (Flutter fork sense)

OS-backed secret storage holding MLS keys, org root keys, and the redb
at-rest encryption key. Desktop uses the `keyring`-backed
`OsSecureSecretStore`; mobile uses a Flutter platform channel into Android
Keystore / iOS Keychain. Protects against other apps and a stolen locked
device; does NOT stop a logged-in attacker with physical access and time on
desktop, and on mobile stops everything below the secure-enclave /
user-presence boundary. (Defined in ADR 0011.)

## At-rest history key

The key used to encrypt the redb persistent history store. Lives in secure
storage, never on disk, so a stolen locked device does not yield message
history. (Defined in ADR 0011.)
## User-presence gate

Mobile behavior where releasing a secret from secure storage requires
biometric or device PIN. Default-on for mosh on mobile; the UI must surface
the prompt and a "locked" state, not silently bypass it. (Defined in ADR 0011.)
