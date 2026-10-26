# ADR 0049: Android background key access and app lock

Date: 2026-10-26.
Status: Accepted security policy; implementation and migration pending.

The shipped Android startup releases its history DEK only after biometric or
device-credential authentication and an Activity foreground gate. That prevents
a cold background process from decrypting messages or validating pending calls
on a locked screen. Retaining the old biometric requirement conflicts with the
background behavior selected in
[ADR 0048](0048-android-background-waiting.md).

After the first Android unlock following reboot, permit the background process
to obtain the database DEK without another biometric prompt. It may decrypt
the database while the screen is locked again and after ordinary process
reclamation. Retain database encryption and Keystore protection; this consciously
removes the biometric gate from each background key release. The Mosh app lock
instead authenticates interactive access to the chat interface, while incoming
calls and explicitly permitted notification previews remain available.

Before the first Android unlock, provide no background reception guarantee.
Credential-encrypted data availability and the policy of an individual Keystore
key are separate: [Direct Boot](https://developer.android.com/privacy-and-security/direct-boot)
does not bypass a key's authentication requirements. See
[Keystore policy](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder).

Migration must preserve the existing DEK and encrypted history. Authenticate
the old wrapping policy through an allowed foreground flow, verify the new
durable wrapping before retiring any old material, and keep the old recoverable
path on failure or interruption. An unavailable/invalid key must not cause
silent key regeneration, database replacement or biometric-recovery recursion.
The concrete storage API and UI re-lock timing remain in the
[design plan](../Proposals/issue-94-android-background.plan.md).

This records the owner's answer to question 10. It amends the Android key-release
policy in ADRs 0011 and 0034 when implemented; desktop key storage is unchanged.
