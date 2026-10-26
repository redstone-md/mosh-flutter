# ADR 0048: Android background waiting over Moss

Date: 2026-10-25.
Status: Accepted architectural direction; detailed design and implementation pending.

Android needs incoming calls and message notifications without FCM or Google
Play services, while retaining a full active mesh in idle conflicts with the
energy goal. Native checks confirmed that the existing relay carrier forwards
encrypted traffic to a connected leaf; the current C API has no economical
waiting mode. See the [feasibility evidence](../Proposals/issue-94-moss-wake.research.md).

Mosh opts into an economical waiting mode in Moss and reuses its relay carrier.
The integration is opt-in for applications using Moss, not for the Mosh user:
Mosh selects waiting automatically when appropriate after initial setup.
Existing defaults for desktop, gaming and SSH consumers remain unchanged.
This keeps transport ownership in Moss and avoids selecting a separate push
provider or hosted broker before one is shown necessary. A reduced startup
configuration alone has not established the required lifecycle or energy use.

Waiting is owned inside the Mosh APK with a persistent quiet notification and
a Stop waiting action. Target background reception after minimizing, screen
locking, task removal and ordinary process reclamation, beginning after the
first Android unlock following reboot. Explicit user stopping requires manual
opening rather than a restart loop. These remain physical-device acceptance
targets, not guarantees established by the relay tests.
Waiting starts after initial setup; the app's Stop waiting action persists an
off preference until explicit re-enabling and must not end an ongoing call.
A refused battery exemption results in limited background availability, without
repeated permission prompts or a claim of guaranteed reachability.
Waiting must not start automatic media or clear-preview downloads. Transfers
already initiated by the user continue, including after Stop waiting; the
saved waiting preference stays off when that work finishes.

On 2026-10-26, the owner expanded the completion boundary to include recovery
of missed messages in private DMs, private groups and public channels. Live
background notifications alone do not complete this slice. Recovery uses
available authorized holders and waits when none is reachable; there is no
central message archive. Private-group recovery respects membership intervals,
including joining, removal and rejoining. Ordinary offline periods retain
access; public channels expose available retained history.

On 2026-10-26, the owner accepted current-administrator endorsements for disputed
historical records. The author's original signature remains necessary; the
authorized administrator attests the publication/admission interval. This trusts
that authority rather than proving creation time cryptographically. Verified
retained endorsements may be forwarded while the administrator is offline.
Organization groups retain their distinct authority rules. Exact wire/storage
contracts still require review before implementation.

Mosh app lock protects chat access independently of background reception.
Names and text are hidden in notifications by default while app lock is active;
the user may explicitly allow their display, including message text on Android's
lock screen. Android's own disclosure settings still take precedence, and
showing a notification preview does not unlock the chat interface.
The configurable UI re-lock delay also applies when Android locks its screen;
its settings do not change the background key-access policy.

The restriction is on Google-hosted event delivery through FCM. Google STUN
remains permitted for address discovery; it does not receive Mosh chat messages
or call offers. This is not a blanket prohibition on network contact with Google.

This direction extends the foreground-only Android scope of
[ADR 0034](0034-android-linked-text-dm.md), retaining the native media ownership
of [ADR 0044](0044-native-call-media-over-moss.md). Key access before app unlock is
defined by [ADR 0049](0049-android-background-key-access.md). This adds no shipped
background guarantees. Android execution rights, safe key migration,
attachment selection, replay/abuse limits, a proposed runtime API and physical
phone energy/reliability checks remain open in the
[design plan](../Proposals/issue-94-android-background.plan.md).

Selecting this direction does not authorize edits to the Moss submodule or
changes to its public API. Those require a concrete reviewed proposal and
coordination with its maintainer before implementation.
