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
the pending call on all receiving devices. Call transfer is a separate task;
user-wide busy behavior remains open in the
[design plan](../Proposals/issue-46-video-calls.plan.md).
