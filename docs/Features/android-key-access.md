# Android history key access

Android's encrypted history keeps its existing 32-byte DEK. Interactive chat
authentication is separate from releasing that DEK after the first system
unlock, as specified by [ADR 0049](../ADR/0049-android-background-key-access.md)
and the [approved access contract](../Proposals/android-background-access-contract.plan.md).
Other platforms keep their existing keychain path.

`initMobileDek` first reads the native background wrapping. A valid wrapping
opens the same encrypted history without an Activity or biometric prompt;
this does not grant access to chat UI. Missing wrapping requires a resumed
Activity before the original `flutter_secure_storage` reader is constructed.
Cold background startup receives `DEK_FOREGROUND_REQUIRED`, including when
there is no database, rather than generating a new identity or history key.
Interactive startup waits for a resumed Activity only in that missing-wrap
case. Legacy migration can require its original prompt followed by a separate
native chat-unlock prompt once; subsequent valid-wrap loading never reads the
legacy biometric storage again. Loading, minting and migration call only
`AndroidAppAccess.initialize()`, preserving the native lock/grace policy.

Migration authenticates and reads the original `history-dek-v1` from its original
`app.mosh.mobile` namespace. Automatic reset and cipher migration are disabled.
The original wrapping is retained. Only after the same DEK has been durably
installed and read back byte-for-byte may the existing Rust bridge receive it.
A fresh foreground installation may mint a key only after the legacy reader
reports absence and the actual history database does not exist.

The native `MoshBackgroundDek` uses the approved credential-encrypted no-backup
file, versioned `MBK1` AES-256-GCM envelope and installation-bound AAD. Android
Keystore generates the IV and wrapping key; per-use authentication is disabled.
Operations serialize across owners. An existing file with a missing alias,
unsupported envelope version, invalid tag or storage failure fails closed.
Writes use `AtomicFile`, explicit file-descriptor sync, commit and decrypted
readback. Ordinary installation never replaces a readable different DEK.

`recoverMobileDek` is a separate explicit foreground action. It reads the
original legacy key and asks the native channel for a fresh strong-or-credential
authentication before repair. Repair may replace a damaged envelope or missing/
invalid wrapping alias, preserving that same legacy DEK. Unsupported versions
and a readable different key are refused. There is no automatic retry loop,
legacy deletion, database reset or guessed replacement key. Channel failures
contain sanitized codes without plaintext key values or provider diagnostics.
Key I/O runs on one worker. Pausing, leaving, screen-off and Activity replacement
revoke queued repair grants; the generation is checked inside the installation
lock immediately before mutation. Key-only repair does not authenticate chats.
On startup corruption, the failed lock screen's Retry is the explicit repair
action; ordinary startup never invokes it automatically.

## Verification

Host tests exercise the existing storage/resolution and platform-channel
boundaries: exact migration, write refusal/readback, interruption, cold loading,
foreground refusal, malformed key material and missing/corrupt wrappings.
They do not establish physical Keystore or biometric behavior.

`BackgroundDekChecks` supplies actual Android Keystore/file fault checks and
refuses to run outside the disposable `.linked_dm_test` application ID. It
requires a fresh disposable installation because it intentionally corrupts its
test envelope and removes its test wrapping alias. Retain your normal Mosh
installation; never enable these fault checks against its application ID.
The runner executes key checks before starting Dart and removes only the fresh
test artifacts it created. Enable them on the isolated build:

```sh
cd android
./gradlew connectedDebugAndroidTest -PmoshLinkedDmTest -Pandroid.testInstrumentationRunnerArguments.backgroundDek=true
```

`AccessExpiryChecks` uses the same isolated runner with
`-Pandroid.testInstrumentationRunnerArguments.accessExpiry=true`. It restores the
non-secret lock preferences after exercising valid cold grace, an acknowledged
visible frame, and native shielding before the expired locked-state event. No
new Dart-frame acknowledgment is supplied at expiry. The deadline covers the
native surface before publishing its new shield generation.

Physical acceptance remains required for legacy biometric cancellation and
migration with real existing messages, first unlock after reboot, cold relocked-
screen reads, Keystore invalidation, explicit recovery and call continuity.
Compiling the native helper or passing host tests does not close IVO-135.
