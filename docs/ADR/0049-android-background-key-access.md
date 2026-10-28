# ADR 0049: Android background key access and app lock

Date: 2026-10-26.
Status: Accepted; implemented on `feat/android-background`, physical migration acceptance pending.

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
On 2026-10-26, the owner also accepted automatic UI re-lock with a configurable
delay after backgrounding, including immediate and minute-based choices. The
accepted choices are immediate, 1, 5, 10 and 30 minutes, with a 1 minute default.
The owner explicitly requires Android screen locking to obey this same delay;
screen locking must not independently force an immediate Mosh lock. Temporary
system dialogs must not cause spurious re-locking. Incoming call controls
remain available without unlocking the chats.
Use one deadline for the continuous absence from interactive chat use; neither
screen locking nor background notifications may restart or extend it.
On return, check expiry before showing chats, including if a delayed timer
could not run while the device slept. The requested
[Telegram comparison](../Proposals/issue-94-android-background.plan.md#telegram-auto-lock-reference)
confirms that screen off need not force immediate app lock.
The approved storage API and lifecycle timing mechanics are implemented as
described in [key access](../Features/android-key-access.md) and
[app lock](../Features/android-app-lock.md). Real-phone migration and lifecycle
acceptance remain required.

This records the owner's answers to questions 10, 14 and 18. It amends the
Android key-release policy in ADRs 0011 and 0034 when implemented; desktop key
storage is unchanged.
