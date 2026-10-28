# Android history key access

Android's encrypted history keeps its existing 32-byte DEK. Interactive chat
authentication is separate from releasing that DEK after the first system
unlock, as specified by [ADR 0049](../ADR/0049-android-background-key-access.md)
and the [approved access contract](../Proposals/android-background-access-contract.plan.md).
Other platforms keep their existing keychain path.

`initMobileDek` reads the native background wrapping. A valid wrapping opens
the encrypted history without an Activity or biometric prompt; this does not
grant access to chat UI. When no wrapping exists and the history database does
not exist either, a fresh installation mints a DEK, installs it durably and
reads it back byte-for-byte before the Rust bridge receives it. A missing
wrapping with an existing database fails closed and never mints. Loading and
minting call only `AndroidAppAccess.initialize()`, preserving the native
lock/grace policy, so chat access prompts once after setup.

The native `MoshBackgroundDek` uses the approved credential-encrypted no-backup
file, versioned `MBK1` AES-256-GCM envelope and installation-bound AAD. Android
Keystore generates the IV and wrapping key; per-use authentication is disabled.
Operations serialize across owners. An existing file with a missing alias,
unsupported envelope version, invalid tag or storage failure fails closed.
Writes use `AtomicFile`, explicit file-descriptor sync, commit and decrypted
readback. Installation never replaces a readable different DEK. Channel
failures contain sanitized codes without plaintext key values or provider
diagnostics. Key I/O runs on one worker.

Mosh has no earlier Android installations, so there is no legacy
`flutter_secure_storage` migration or repair path. A damaged wrapping shows the
failed lock screen; there is no automatic reset or guessed replacement key.

## Verification

Host tests exercise the storage/resolution and platform-channel boundaries:
cold loading, minting with readback, refusal to mint over existing history,
malformed key material and missing/corrupt wrappings. They do not establish
physical Keystore behavior.

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

Physical acceptance remains required for first unlock after reboot, cold
relocked-screen reads, Keystore invalidation and call continuity.
Compiling the native helper or passing host tests does not close IVO-135.
