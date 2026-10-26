# Android incoming call ownership

Integration status: the native ledger and application bridge are implemented.
Android notification actions, media-service promotion and physical-phone
acceptance must be integrated before this layer is released.

The installation owner publishes authenticated native call transitions without
opening a chat or polling the chat list. It uses the same DM protocol, current
linked-device selection and native media owner as foreground calls. Desktop
keeps its existing presentation and protocol service.
Both owners share the existing call-selection policy: unrelated notification
revisions retain the selected call, while an explicit Answer selects its exact
conversation. Replaying another conversation's cancellation cannot hide it.

The encrypted `background_delivery` table retains each call notification's
opaque OS identity, phase revision and one-use action capabilities. Capabilities
contain 256 random bits. Native validation checks the exact current session,
call, participating-device binding, phase, local expiry and process incarnation
before consuming one. A known call ID cannot authorize an exported Activity
intent. Reclamation invalidates old capabilities; cancellation is a newer
revision of the same notification. Exact acknowledgements cannot erase a newer
phase. Terminal acknowledged records are retired. Capabilities never enter call
history or unencrypted notification metadata beyond their required action intent.
Consumption and replacement of retry buttons share one encrypted transaction;
permission refusal or a failed control cannot leave a consumed button stranded.

Answer opens the existing Activity. The action returns a current call target;
it does not accept the call, unlock chats or start capture. The existing call
orchestrator requests microphone permission from a visible Activity, then calls
the normal native accept operation, which rechecks current selection. Camera
permission and media-service promotion precede their capture commands. Stale
selection, missing permission or refused service promotion cannot authorize
late capture. Decline and hangup reuse the existing native controls and do not
open chats. A failed decline retains the existing retry semantics and gets new
one-use buttons instead of reviving a spent capability.

Incoming ringing and its 30-second first-receipt deadline belong to the native
owner. Retransmitted offers do not extend the deadline. Flutter retains the
outgoing tone and current call presentation, including floating video and PiP;
it yields incoming notifications and ringing to the Android application owner.
Every OS publication applies the current native privacy policy. Names and text
remain separate choices; notification actions do not extend chat access.

Verification includes independent bridge installations receiving call offers
without widget polling, exact capability replay/cancellation checks, real
redb refusal and encrypted-at-rest checks, and media commands held behind the
platform promotion boundary. These checks do not establish physical handset
Doze, OEM delivery, lock-screen audio routing or energy acceptance.

The native call synchronization and action-consumption methods retain their
complete redb transaction closures together. They exceed the normal function
length guidance to keep state validation, capability rotation and commit failure
handling reviewable as one atomic operation. Independent-installation tests keep
their protocol setup and assertions together for the same reason.
