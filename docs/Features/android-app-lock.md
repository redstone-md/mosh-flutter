# Android app lock

Android's app lock protects chat routes independently of the retained call and
native session owners. Privacy settings offers immediate, 1, 5, 10 and 30 minute
delays, with a 1 minute default. There is no new disable-lock option.

The native access owner uses `SystemClock.elapsedRealtime`, including deep sleep,
and Android's boot count. Leaving interactive chat use starts one grace deadline.
Screen off, repeated background events and call controls retain that deadline.
Before showing chats, resume validates it again; a delayed timer is insufficient.
Only actually rendered, interactive chats end that absence. Call-only frames,
notifications and background sync cannot refresh the grant.
Here protected chat access includes the session list and settings: navigating
those protected screens is ordinary interactive app use, not a call-only action.

The non-secret `app.mosh.access.v1` preferences persist synchronously with
`SharedPreferences.commit()`. They contain the approved version, delay, boot
count, elapsed deadline and locked/interactive/grace state. Only valid same-boot
grace can survive a cold process. Former interactive state, missing boot data,
expired/future-invalid time or a refused save cannot grant chat access. Corrupt
non-secret metadata starts locked; successful authentication can replace it
without changing encrypted key material.

API 30+ uses Android's platform BiometricPrompt with strong biometrics or device
credentials. API 26–29 uses device-credential confirmation. A canceled request,
detached Activity, stale callback or unavailable credential leaves chats covered.
The existing localized lock screen supplies Retry. Key access remains separate;
loading or migrating a key never authenticates chats. A first legacy migration
can therefore show its legacy key prompt and then the chat prompt once. Ordinary
startup uses the new background key without that legacy prompt; valid grace
also returns to chats without a prompt. A delayed interactive-state save cannot
unlock an expired or locked policy.

Inactive-only permission dialogs do not start a deadline. A document picker
that stops Mosh starts the ordinary bounded grace: pressing Home from the picker
does not give Mosh another departure callback, so exempting its entire lifetime
would leave access open indefinitely. Returning before expiry needs no unlock;
a long picker can require it, including with the immediate setting. Screen off
does not extend that deadline. Configuration changes retain the native owner.

## Presentation boundary

The chat gate sits inside the existing Android call host. It preserves drafts
offstage while locked, stops their focus/tickers and refuses read/view marks or
automatic attachment opening. The call owner and its voice/video controls remain
mounted outside. Root-Navigator protected popups are discarded on lock and a late
protected popup is removed before painting. The existing call-device dialog is
explicitly permitted while locked. Desktop behavior is unchanged.

A native black shield covers the old Flutter surface on resume/screen unlock.
The installation-owned access channel publishes a revision and shield generation
with every snapshot. The private `protectedFrameReady` handshake carries that
generation and whether the painted frame exposes chats. Native code drops only
the current shield; a chat-visible acknowledgement also rechecks current expiry.
An expired or stale acknowledgement cannot expose the old frame. A locked or
call-only frame can release the shield so the unlock UI/controls remain usable.
This handshake changes no public Rust or network protocol.

## Checks and limits

The host JVM access probe drives the production policy through clock/storage
adapters: all delays, the original screen-off deadline, exact expiry, cold grace,
boot fencing, elapsed rollback and refused persistence. Run it with the existing
`node scripts/android-context-check.mjs` bootstrap checks.

Focused Flutter checks exercise the real channel adapter and chat gate, canceled
authentication, stale responses, blocked storage, preserved drafts, protected and
call popups, the saved setting and the existing call/PiP/navigation widgets.
Production Kotlin/Java compiles against Android 36 and the pinned Flutter APIs.
These checks do not establish physical biometric/PIN behavior, OEM lifecycle
reliability, pixel-level resume timing or actual call continuity on a phone.
Those remain device acceptance, together with IVO-135's legacy key migration.

See [ADR 0049](../ADR/0049-android-background-key-access.md) and
[runtime ownership](android-runtime.md).
