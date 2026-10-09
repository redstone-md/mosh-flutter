# ADR 0043: one device per user in a call

Date: 2026-10-08
Status: Accepted

For [issue 46](https://github.com/redstone-md/mosh-flutter/issues/46), a private
DM call connects two Mosh users, each represented by one participating device.
All available devices of the contact can ring; answering selects one receiving
device and stops ringing on the others. This follows the user/device distinction
in [ADR 0030](0030-linked-desktop-dm-clients.md) without making linked devices
additional media participants.

Targeting only the original installation would prevent a linked device from
answering for the same contact. Allowing several devices to independently accept
and send media would turn a two-person call into a call with additional media
participants. The chosen model requires authenticated device selection and a
single agreed answer before enabling media; the existing voice controls do not
yet implement that coordination. Explicit refusal on one receiving device ends
the pending call on all receiving devices. A pending outgoing or admitted incoming
call reserves its user's occupancy through ringing, setup, active media and
reconnection. A free sibling cannot admit an unrelated call while that occupancy
is known. This follows the account-wide policy demonstrated in
[Telegram's call flow](https://core.telegram.org/api/calls#one-to-one-calls).

A remaining reachable device may start or accept a call without permission
from unavailable siblings. Known authenticated occupancy blocks another call;
during network separation the policy is best effort and different devices can
hold overlapping calls. This chooses availability over strict account-wide
coordination that could block calls when an authority or quorum is unavailable.
When devices discover overlapping calls, preserve the existing calls and inform
the user. Block new calls until all calls involved have ended. Do not choose a
winner by terminating an active conversation. This is an exception to normal
single-call occupancy, not support for call waiting or extra media participants.

The caller confirms the first eligible answer or refusal. Until that confirmation,
a receiving device's answer remains pending and must not start media. If refusal
wins, all devices stop ringing. If an answer wins, it selects one receiving
device; later refusals from nonparticipating devices cannot terminate the accepted
call. Only its two participating devices may end that call. Authenticate these
transitions and bind them to the call and selected device identities.

Simultaneous offers between the same users merge into one call before media
starts. Both sides must converge on one call identity and caller authority while
preserving each user's chosen microphone/camera state. This does not merge two
already active calls. Call transfer is a separate task. See the
[design plan](../Proposals/issue-46-video-calls.plan.md) for implementation stages
and acceptance scenarios.
