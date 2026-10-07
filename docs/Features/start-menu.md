# Start menu

IVO-50 redesigns the chat pane shown when no conversation is open: a
welcome hero over four ways to begin, each opening its step in place.

## Behavior

- **Menu.** A plain greeting (no caps, no tracking), the title "Start a
  conversation" and a subtitle that promises encryption for private chats
  and groups only. There is no fact list: a static claim such as
  "encrypted history" can be false while the storage warning shows. The
  hero illustration sits on
  the right from 760px of pane width. Cards sit four to a row from 1000px,
  two by two from 520px and stack as compact rows on a phone.
- **Steps.** Each card opens its step in place; the rail stays. A step
  shows Back, its illustration, title and lead, then its form on a raised
  card. Every step stays mounted, so typed text and a created invite
  survive a trip to the menu. `/join` (deep links) shows the join step on
  its own page; its Back opens the menu.
- **Private chat.** Create makes an invite on request, never on entry,
  because each invite adds a pending chat to the list. The result offers
  copy, a new link and Open chat. A new link makes a new pending chat; the
  old link keeps working. The footer says what the core enforces: until the
  contact connects, anyone holding the link can use it.
- **Group.** The name is required. Create copies the invite; the result
  offers copy, Open group and "Create another group". There is no avatar
  or description: the core does not carry them.
- **Join with a link.** The preview names what the link opens (private
  chat, group, organization) and the name a group or organization link
  carries. Nothing is fetched before Connect.
- **Public channel.** A warning says the channel is not encrypted before
  anything is typed. Names follow the core rule (Latin letters, digits,
  `-`, `_`); `news`, `dev` and `community` fill the field. The app opens the
  channel by the name the core normalized (`#News` opens `news`).
- **Display name.** It is edited in Settings → Profile, not here.

## Motion

Values follow transitions.dev recipes, all on `cubic-bezier(0.22, 1, 0.36, 1)`
(`start/start_motion.dart`):

- Texts reveal (18): hero lines rise 12px from a 3px blur over 500ms, 40ms
  apart; cards follow 80ms apart.
- Page fade-through: the leaving page fades out in the first 40% of 250ms
  sliding 8px toward its side, then the shown page fades in. Every page is
  centred in a box at least as tall as the pane, so the menu does not jump
  when a shorter step replaces it. No blur: it reads as mush and costs a
  full-pane filter on the illustration.
- Card hover tilt (19): up to 6° toward the pointer, following in 400ms and
  settling in 1000ms, under a soft glare. Hover and keyboard focus light the
  card the same way; the arrow fills and nudges forward (24).
- The hero illustration stays still.

Under reduced motion everything is shown at rest and steps swap in place;
cards still light on hover and focus.

## Ownership

`NewSessionPanel` owns the current page; `StartPages` keeps the pages
mounted and slides between them. `StartMenu`, `StartHero` and `StartCard`
draw the menu; `StartStep` frames a step. The step widgets
(`ChatCreateStep`, `GroupCreateStep`, `OnboardJoinStep`, `ChannelJoinStep`)
keep their bridge calls. Illustrations and their prompts live in
[`assets/start/`](../../assets/start/README.md).

## Known gaps

- With the storage warning shown, the pane is taller than the window by
  the banner's height, so it scrolls.

- A private chat invite is not single-use in the core: until a contact
  connects, a second person can use it, and a new link does not revoke the
  old one. The copy states this instead of promising one-time use.
- Group avatars and descriptions, and a preview fetched before joining,
  need core support.

## Checks

`test/features/onboarding/` covers the layout per width, hover, focus and
reduced motion, every step through the menu, and the normalized channel
route. `start_preview_test.dart` renders review frames with
`--dart-define=START_PREVIEW=<dir>`.
