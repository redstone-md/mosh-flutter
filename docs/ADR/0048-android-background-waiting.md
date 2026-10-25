# ADR 0048: Android background waiting over Moss

Date: 2026-10-25.
Status: Accepted architectural direction; detailed design and implementation pending.

Android needs incoming calls and message notifications without FCM or Google
Play services, while retaining a full active mesh in idle conflicts with the
energy goal. Native checks confirmed that the existing relay carrier forwards
encrypted traffic to a connected leaf; the current C API has no economical
waiting mode. See the [feasibility evidence](../Proposals/issue-94-moss-wake.research.md).

Use an explicit opt-in waiting mode in Moss and reuse its relay carrier.
Existing defaults for desktop, gaming and SSH consumers remain unchanged.
This keeps transport ownership in Moss and avoids selecting a separate push
provider or hosted broker before one is shown necessary. A reduced startup
configuration alone has not established the required lifecycle or energy use.

The restriction is on Google-hosted event delivery through FCM. Google STUN
remains permitted for address discovery; it does not receive Mosh chat messages
or call offers. This is not a blanket prohibition on network contact with Google.

This direction extends the foreground-only Android scope of
[ADR 0034](0034-android-linked-text-dm.md), retaining the native media ownership
of [ADR 0044](0044-native-call-media-over-moss.md). It does not add shipped
background guarantees. Android execution rights, key access before app unlock,
attachment selection, replay/abuse limits, a proposed runtime API and physical
phone energy/reliability checks remain open in the
[design plan](../Proposals/issue-94-android-background.plan.md).

Selecting this direction does not authorize edits to the Moss submodule or
changes to its public API. Those require a concrete reviewed proposal and
coordination with its maintainer before implementation.
