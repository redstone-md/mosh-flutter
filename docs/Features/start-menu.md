# Start menu

IVO-50 redesigns the chat pane shown when no conversation is open: a
welcome beside four ways to begin, each opening its step in place.

## Behavior

- **Menu.** The Mosh mark, the title "Start a conversation" in one colour
  and a subtitle that promises encryption for private chats and groups
  only. The four actions are rows in two groups: "End-to-end encrypted"
  (private chat, group, join with a link) and "Open to everyone" (public
  channel). Every invite link opens a DM, group or organization, all
  admitted through MLS, so the join row belongs to the encrypted group.
  Icons take the conversation type accents the rail uses. From 860px of
  content width (the pane less its 32px side padding, so a 924px pane) the
  welcome sits left of the list; narrower panes stack them, and below
  480px of content width the mark is dropped so the actions come first.
- **No decoration that claims or performs.** No eyebrow, tracked caps,
  accent-coloured title word, fact list, parallax, card tilt or glare. A
  static claim such as "encrypted history" can be false while the storage
  warning shows, so the menu makes none beyond the subtitle.
- **Steps.** Each row opens its step in place; the rail stays. A step
  shows Back, a small illustration, title and lead, then its form on a raised
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

All on `cubic-bezier(0.22, 1, 0.36, 1)` (`start/start_motion.dart`):

- Texts reveal (transitions.dev 18): the mark, title, subtitle and list
  rise 12px from a 3px blur over 500ms, 40ms apart.
- Page fade-through: the leaving page fades out in the first 40% of 250ms
  sliding 8px toward its side, then the shown page fades in. Every page is
  centred in a box at least as tall as the pane, so the menu does not jump
  when a shorter step replaces it. No blur: it reads as mush and costs a
  full-pane filter on the illustration.
- Row hover: hover and keyboard focus raise the row from `bg1` to `bg2` in
  140ms and edge the chevron forward. Nothing leans, glares or drifts.

Under reduced motion everything is shown at rest and steps swap in place;
rows still lift on hover and focus, without the chevron moving.

## Ownership

`NewSessionPanel` owns the current page; `StartPages` keeps the pages
mounted and fades between them. `StartMenu` lays out `StartHero` and
`StartActionList` (rows are `StartRow`); `StartStep` frames a step. The step widgets
(`ChatCreateStep`, `GroupCreateStep`, `OnboardJoinStep`, `ChannelJoinStep`)
keep their bridge calls. Illustrations and their prompts live in
[`assets/start/`](../../assets/start/README.md).

## Known gaps

- `hero.png` carries transparent margins; `StartHero` pulls the mark left
  by the art's share of the canvas so it lines up with the title.
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
