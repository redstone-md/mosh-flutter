# ADR 0018: one Conversation module for the DM, the channel and the group

## Status

Accepted. Follows ADR 0017, which made the Gateway take the conversation
target.

## Context

ADR 0017 removed the kind from the Gateway, but the UI above it was still
written three times. A DM, a channel and an org group each had their own
controller, screen body, message row and message list view, and the
controllers were 84% the same lines, the bodies 93%, the rows 85%. Every
change to how a conversation behaves — a delivery-status tweak, an attachment
edge case, a rule about when the composer clears — had to be made in three
files and three test suites, and drifted whenever one copy was missed.

The three parts really are one conversation. What differs is small and
nameable:

- a DM shows a crypto footer, can carry a call, and shows delivery ticks;
- a channel says its messages are public and hides the MLS badge;
- a group says its messages are encrypted, can warn that a rejoin is needed,
  and can offer an org admin the members who are missing from it.

## Decision

One Conversation module, driven by the target. It lives in
`lib/src/features/conversation/`.

```mermaid
flowchart TD
    Dm[DmScreen]
    Ch[ChannelScreen]
    Gr[GroupScreen]
    Screen[ConversationScreen]
    Body[ConversationScreenBody]
    Ctrl[ConversationController]
    List[ConversationMessageListView]
    Row[ConversationMessageRow]
    Snap[conversationSnapshotProvider]
    Kind["activeSessionProvider / channelSnapshotProvider / groupSnapshotProvider"]

    Dm -->|"its header, its target"| Screen
    Ch -->|"its header, its target"| Screen
    Gr -->|"its header, its target"| Screen
    Screen --> Body
    Screen --> Ctrl
    Body --> List
    List --> Row
    Body --> Snap
    Ctrl --> Snap
    Snap --> Kind
```

Each kind supplies its app bar and nothing else. The shared screen hands the
header a `ConversationChrome` -- the search text, the filter, the two panels
and the leave action -- so the header and the body read one bundle instead of
a dozen loose values. `DmScreen` also keeps whether the user has confirmed
this session's safety number in person, which no other kind has.

The three generated snapshots map into one view. It is sealed, so each kind
keeps its own source snapshot for the surfaces that genuinely need it — the
peer-status drawer, the group's rejoin flag, the leave dialog's label — and
nothing needs a cast.

```mermaid
classDiagram
    class ConversationSnapshot {
      +AnyConversationTarget target
      +String ownDeviceName
      +String ownFingerprint
      +List~ConversationMessage~ messages
      +List~AttachmentView~ attachments
      +attachmentView(id) AttachmentView
    }
    class DmConversation {
      +SessionSnapshot source
    }
    class ChannelConversation {
      +ChannelSnapshot source
    }
    class GroupConversation {
      +GroupSnapshot source
    }
    class ConversationMessage {
      +String fromDevice
      +String? fromFingerprint
      +bool own
      +String senderKey
      +bool canRetry
    }

    ConversationSnapshot <|-- DmConversation
    ConversationSnapshot <|-- ChannelConversation
    ConversationSnapshot <|-- GroupConversation
    ConversationSnapshot --> ConversationMessage
```

The ticket asked for the extras -- the group's admin flag and org binding,
the DM's calls -- as optional fields on one view. They are not there. The
sealed source snapshot carries them instead, so a reader cannot pick up a
field its kind never fills, and the peer-status drawer keeps the exact type
it already reads. The effect the ticket wanted is the same: one view, one
provider, and the extras out of the shared path.

Two details make the merge behave:

- `own` is worked out while mapping. A DM compares device names; a channel
  and a group compare fingerprints, because two members can share a display
  name but never a fingerprint.
- `conversationSnapshotProvider` does not poll. It watches the kind provider
  the app already has and maps the result, so there is still one poll per
  conversation and `ref.invalidate(channelSnapshotProvider(name))` and its
  siblings keep working. The sessions list, the headers and the drawer read
  those providers unchanged.

## Consequences

- `channel_controller.dart`, `group_controller.dart`, `dm_screen_actions.dart`,
  the three screen bodies, the three message rows, the three message list
  views and `group_attachment_open.dart` are deleted. The three screens are
  now 70 to 95 lines each and hold no conversation logic.
- Conversation behaviour is tested once and run over all three targets, from
  `test/support/conversation_cases.dart`. Six tripled suites are gone.
- A fourth conversation kind needs a target, a header and a mapper.
- The kind still decides three small things in the shared row and body: the
  fingerprint chip, the MLS badge and the delivery ticks. Those are `switch`
  arms on `ConversationKind`, not separate widgets.
- The Rust side and the frb facade are untouched.
- The screen now re-marks the active conversation when the router reuses it
  for a different one. The three old screens only did that in `initState`,
  so a reused screen left the unread lifecycle pointing at the conversation
  the user had just left.

## Size exception

`ConversationController` is about 295 lines, over the 200-line type limit in
AGENTS.md. Merging the three controllers is the point of this ADR, and the
class has one responsibility: what one conversation screen is doing. Every
plausible split -- sends here, attachments there -- would put one screen's
work back in two places, which is what this change removed.

Scope: `ConversationController` only. Its state and its result types already
live in `conversation_state.dart`.

Revisit it when a fourth thing joins send / attachments / peer invites, or
when a kind needs work the others do not. Either would be a real second
responsibility, and then the split has a seam to follow.

## Alternatives considered

- Keep the three implementations and only share helpers: rejected. That is
  what the code already did, and the copies still drifted.
- One snapshot class with every kind's fields nullable: rejected. Every
  reader would have to know which fields its kind fills, and nothing would
  stop it reading a field that is always null.
- Have `conversationSnapshotProvider` poll the Gateway itself: rejected. It
  would double the polling and split invalidation between two providers.
