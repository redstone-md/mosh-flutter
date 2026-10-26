# Android access contract for IVO-134/135

Status: approved by the owner on 2026-10-26 for implementation, including the
platform channel, key envelope, preference format and authentication API ranges.
Implementation and physical-device acceptance are pending; no shipped key policy
has changed yet.

## Boundaries

Keep one native runtime, database and DEK. Split interactive authentication from
key loading. Leave desktop key storage and Rust bridge signatures unchanged.
Use Android's existing Keystore, Cipher, AtomicFile and authentication APIs;
no new cryptographic algorithm or Flutter package is required.

The pinned flutter_secure_storage 10.3.1 remains the **foreground-only legacy
reader**. Its AES biometric path requires authentication on a secured device
even with `enforceBiometrics: false`. Ordinary writes use SharedPreferences
`apply()`, which does not establish disk durability. Its defaults also permit
error-triggered deletion and cipher migration. Merely changing that constructor
is therefore not a safe durable background-key migration.

## New platform channel

Channel: `app.mosh.mosh/access`, installation-owned, attached to the retained
engine. Calls return typed platform errors without secret values in messages.

| Method | Input | Result |
| --- | --- | --- |
| `readBackgroundDek` | none | 32 bytes, absent, or an error |
| `installBackgroundDek` | exactly 32 bytes | success only after durable readback |
| `recoverBackgroundDek` | exactly 32 legacy DEK bytes | explicit authenticated foreground repair, then durable readback |
| `authenticateChats` | localized reason | authenticated / canceled / unavailable |
| `readAccessState` | none | delay, boot marker, elapsed deadline and state |
| `saveAccessState` | validated access state | success after synchronous persistence |

Serialize key operations. Never overwrite a readable key with a different DEK.
A missing alias alongside an existing envelope is an error, not permission to
generate a new alias. Unknown envelope versions and invalid authentication tags
fail closed. Raw DEK bytes already cross Dart/Rust today; do not log, persist in
plaintext, attach to saved Activity state or include in crash reports.

## Key envelope and migration

- Keystore alias: `app.mosh.mobile.background-dek.v1`, AES-256-GCM, randomized
  encryption required, authentication-per-use disabled. Do not require the
  screen to remain unlocked. Gate access on `UserManager.isUserUnlocked` and
  use credential-encrypted application storage, not device-protected storage.
- File: `noBackupFilesDir/background-dek-v1`, written with AtomicFile. Binary
  envelope: four-byte ASCII `MBK1`, 12-byte random IV, 48-byte ciphertext/tag
  for the 32-byte DEK. AAD: UTF-8 application ID followed by `/background-dek/v1`.
  Use Android's Cipher and generated IV; do not implement encryption primitives.
- Synchronize writers and AtomicFile recovery. Finish the write, reopen and
  decrypt the committed file, compare all 32 bytes, then report success.
- Existing installation: authenticate/read the original `history-dek-v1` through
  its original `app.mosh.mobile` namespace only in a resumed Activity. Disable
  automatic reset and algorithm migration on this legacy read. Install **that
  exact DEK**, read it back and use the existing `setHistoryDek` bridge.
- Retain the legacy wrapping as recovery material; no deletion is part of this
  migration. A failed/interrupted new write never destroys the old wrapping.
  A later retirement, if needed, requires its own verified migration proposal.
- A fresh installation first durably installs a newly generated DEK and only
  then opens its encrypted store. If any database already exists and neither
  wrapping yields a valid key, show a recoverable error; never mint a replacement.
- An existing valid new wrapping takes precedence. If it is damaged, cold
  background startup fails closed; an explicit authenticated foreground recovery
  may reinstall the same legacy key through `recoverBackgroundDek`, never a
  guessed or newly minted key. This repair path requires a current foreground
  authentication and successful legacy read; ordinary install/read cannot
  overwrite a damaged envelope or recreate its missing alias automatically.

## Interactive authentication and grace

Authentication is independent of key loading and never creates chat access from
a notification/call action. Preserve strong biometrics or device credentials:
API 30+ uses platform BiometricPrompt with `BIOMETRIC_STRONG | DEVICE_CREDENTIAL`.
API 26–29 uses the platform device-credential confirmation flow because that
combined authenticator choice is not supported consistently there. This means a
PIN/pattern/password prompt on older phones. No weak-face fallback is introduced.
Cancellation, Activity detachment or unavailable credentials keeps chats covered.

The standard local_auth plugin was considered: its current Android implementation
allows weak biometrics as well as strong ones, without a strength option. A small
Android adapter preserves the current strong-or-credential policy without a new
dependency or a fork. Before implementation, verify the platform APIs against the
minimum SDK and compile the adapter for both old and current API branches.

Persist non-secret preferences in a separate application-private preference file:
`app.mosh.access.v1`. Fields: version=1, delay seconds (0/60/300/600/1800,
default 60), boot count, elapsed-realtime deadline and state (locked/interactive/
grace). A record marked interactive is not a reusable grant after cold startup.
Only a valid same-boot grace deadline may survive process reclamation. Missing,
future-invalid or unverifiable boot/time metadata requires authentication.

The UI gate observes actual departure from interactive use. Screen off starts
the same grace period if needed; it never restarts an existing one. Inactive-only
system dialogs/file pickers are not a departure. On resume, validate elapsed time
**before** mounting protected chat content. Authentication success grants access
only to the current foreground request; cancellation/stale results cannot unlock
a newer screen. Background events and call actions never refresh the deadline.
Calls, waiting and user-started transfers remain mounted outside the chat gate.

## Verification before completion

Use the already approved adapter seam for deadline/authentication/storage faults;
test every timeout, same-boot restart, clock discontinuity, no-content flash,
cancel, stale auth result, interrupted writes and byte-identical key migration.
Use a physical Android for actual legacy biometric migration, reboot/first unlock,
cold relocked-screen loading, Keystore invalidation and call continuity. A host
test or successful build cannot establish those conditions.

## Sources

- Pinned source: flutter_secure_storage 10.3.1 `AndroidOptions`,
  `FlutterSecureStorage.writeUnsafe`, `handleKeyMismatch` and
  `KeyCipherImplementationAES23.generateSymmetricKey`, inspected locally.
- [Android Keystore policy](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder).
- [AtomicFile](https://developer.android.com/reference/android/util/AtomicFile).
- [BiometricPrompt authenticators](https://developer.android.com/identity/sign-in/biometric-auth).
- [Local Auth API](https://pub.dev/packages/local_auth), with Android 2.3.0
  package source checked through its published archive on 2026-10-26.
