# ADR 0050: Persistent read marks

Date: 2026-11-04.
Status: Accepted for GitHub issue 102.

Unread badges were derived in Dart from poll-to-poll growth and kept only in
memory, so the first snapshot after launch counted as read. Messages that
arrived while Mosh was closed, or that recovery delivered after launch, got no
indicator.

## Decision

The core owns what the user has seen, per conversation and per installation,
as one encrypted row in the additive `read_marks` table. The key is the history
label and the conversation id. `ConversationRuntime` holds the marks for its
kind, so DMs, groups and channels share one implementation.

A mark has two fields:

- `floor_ms`: where the installation starts counting. It is just after the
  newest message the conversation holds when its mark is created, or the
  creation time for an empty conversation. Messages sent earlier are history
  and never count: existing chats on the first run of this version, an archive
  imported onto a linked device ([ADR 0031](0031-linked-desktop-dm-history.md)),
  a channel's backlog. Messages sent after an existing chat's newest stored one
  and recovered after the upgrade still count.
- `seen`: how many incoming messages since the floor the user has had on
  screen.

Incoming means not by the installation's own author (device name in a DM,
fingerprint in a group or channel) and not recorded as own, and not a service
line or a call log entry. Recovered group records never claim ownership, so
the author decides. A message the user hid still counts, so hiding a seen
message cannot hide the next one. Counting keeps the number right in any
arrival order. Which messages are unread is read in send order, the order
history is replayed in, so the divider stays put across a restart; a message
recovered after newer ones were seen moves the divider to the newest unread
position instead of onto itself.

`poll` and `list` attach `UnreadState { count, first_unread_message_id }` to
each snapshot. The existing `markViewed` bridge call now marks all three kinds
read, before any inbound drain, so only what the last poll showed counts as
seen. The conversation screen sends it only while the app is resumed: an
unfocused window keeps showing the chat, but its new messages stay unread,
keep their badge and raise a toast. Read receipts follow the same rule.
Leaving a conversation deletes its mark with its history. A mark that cannot
be read is not replaced; that answer uses a temporary one.

Dart shows the count as the rail badge, hides it for the conversation on
screen in a focused window, and toasts only when a count grows during a
session. The conversation screen takes the first unread id when the
conversation comes on screen and keeps the divider there after the count
clears.

## Boundaries

- Groups: another person cannot add this installation to a group or create a
  DM on it. Plain groups are joined from an invite the user opens; org groups
  from an offer the user accepts, and org offers are recovered.
- DM offers made inside a channel or a group are held in memory only. One
  that arrived before a restart is gone after it, and one sent while Mosh was
  closed is not recovered. This change does not fix that; it needs durable,
  recoverable DM offers.
- External invite links are not invitations until the recipient opens them.
- Android uses the same marks and badges. Its background delivery and
  notifications follow [ADR 0048](0048-android-background-waiting.md); a
  message received in the background is unread until a chat shows it.
- A message sent before the floor never counts. Clock skew between sender and
  receiver shifts that edge by the skew.
- Marks are per installation; linked devices do not share what was read.
- Delivery while Mosh is stopped is unchanged: counts appear once an
  authorized source delivers the messages after launch.

## Alternatives

A Dart file in the app data directory, like the language and rail-layout
preferences, would need no bridge change but would store conversation ids and
channel names in plaintext, against [ADR 0011](0011-secure-storage-and-threat-model.md)
and [ADR 0012](0012-port-strategy-what-goes-to-dart-vs-mosh-core.md).
