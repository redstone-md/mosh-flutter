# Chat visual consistency

## Scope and checks

The follow-up to the chat redesign addresses the user's reported corner-radius
drift, displaced voice play icon, and indistinguishable conversation types.
The subsequent approved [bubble and header polish](chat-message-header-polish.md)
evolves message geometry and header rhythm; the current shape table below
includes that follow-up.

1. Reuse the Material theme and existing message, attachment and avatar widgets.
   Put shared corner geometry in one token file and type cues in one component.
2. Keep file and voice content within the message's surface. Center voice play
   and constrain the waveform to the width actually available.
3. Check the voice regression, all three conversation types at desktop/mobile
   widths, existing controls and attachment behavior, analysis and coverage.

The shared control theme also affects standard buttons outside chat. Existing
widget tests cover those callers; physical Windows rendering and native audio
remain checks on a real device.

## Working brief

- Intent: someone reading, finding and replying to conversations on a desktop,
  with the same familiar controls on a phone.
- Hierarchy: messages lead; the list supports navigation; times and transfer
  metadata are quieter than content.
- Domain: personal contacts, group membership, public channels, invitations,
  voice clips and shared files.
- Color world: the theme's warm dark surfaces and off-white text, with the
  saffron primary, channel blue and a muted sand for groups.
- Signature: conversation type has the same glyph in the list, header and
  details, independently of runtime security indicators. (Its accent colour
  and the glyphs in the filters went with MOSH-134.)
- Defaults corrected: inherited Material pill shapes, separately rounded
  cards inside messages, and identical green avatars for every type.
- Depth and surfaces: existing dark surface steps and subtle edges; no new
  shadows or decorative gradients.
- Typography: existing Mosh theme; message text stays at 14px, previews and
  metadata use the existing smaller steps and foreground levels.
- Spacing: 4px base, 12px horizontal text insets, 8px file/media insets and
  8px composer control inset.
  The waveform takes the remaining space, while play retains its 40px hit target.

## Shape ownership

`lib/src/app/mosh_shapes.dart` defines the chat geometry. Components reference
these tokens instead of choosing their own corner radius.

| Element | Radius | Relationship |
| --- | ---: | --- |
| Search, settings, filters, standard buttons | Pill | One shape across states; the Components cards since MOSH-133 and MOSH-134 |
| Conversation rows | 16px | Stable in selected and unselected states |
| Message outside corners | 20px | 8px joins on the sender's side within a run, whatever the bubble holds; the Message card since MOSH-135 |
| Composer control group | 16px | 8px control corner plus 8px inset |
| Media and file icon surfaces | 12px | 20px message corner minus a uniform 8px inset |

Since MOSH-135 the feed is drawn from the Message, Feed rows, Attachment,
Voice message and Search and selection cards. A bubble has the same 8px
padding on every side; its text, its sender line and the caption of a picture
are set in 8px further at the start and 4px at the end, which keeps the time
and the delivery marks 12px from the edge. A file, a picture or a voice
message rides above the text, which is then its caption and wraps at its
width. The time ends the last line of the text; a file or a voice message
alone keeps it in its own last line, under the transfer bar while the file
arrives, and a picture keeps a line of its own for it. The one action of a
file is its 40px plate, so the time never moves it.

The message-search segment uses its outer 8px corner minus its 3px inset.
Avatars and voice play remain circles because they are identity and transport
controls, rather than rectangular fields. Progress bars retain their small
end caps. Modal geometry remains owned by the existing modal components.

The chat list's search is a pill on its own plate with no resting edge; the
focus ring takes the edge's place (MOSH-134).
The composer input stays borderless when disabled as well as when enabled.

## List controls

Since MOSH-134 the controls are drawn from the Chat list card: starting a
conversation is the primary button, and the search is a pill as tall as a
control (40px on desktop, 48px on a phone) with the shortcut in a keycap.
[Chat list layout](chat-list-layout.md) has the current geometry.

Type filters retain Material single-selection, keyboard focus and hover
feedback. Since MOSH-134 they are the Filter chip card: 32px pills that name
the type in words, with a thin edge when inactive and one `secondaryContainer`
fill when selected. Native targets are 40px
on desktop and 48px on mobile. The targets' invisible insets are included in
the 8px search/filter gap and 12px filter/list gap. Large text can grow the
controls, and filters remain horizontally scrollable at narrow widths. A 2px
focus outline sits outside the surface without changing its size; the scroller
reserves 2px at each horizontal edge so that outline stays visible.

## Embedded files and voice

Files use a flat row within the bubble instead of a second rounded card: the
File card, which the list of shared files in the details reuses on a surface.
Media previews clip to the embedded radius. A failed transfer is told by the
error colour of its plate and its line, and the same plate tries again. The preview height comes from the inline miniature's
JPEG/PNG header, including legacy EXIF orientation, before any decode. It
scales with the available width (at most 320px), clamped to 120–260px, or is
200px when unknown. Miniature, clear preview and original fill that box with cover
fit, so their arrival never moves the list. Miniatures are cached by their
encoded value and reappear in the first frame when a chat is reopened.
Base64 bytes and parsed sizes use a 4 MiB cache payload budget. Keys are
budgeted as UTF-16; entries above 128 KiB are decoded without retention.
Download, cancel, retry and open behavior is unchanged.

Voice uses the same message surface. Play/pause is centered without an extra
translation, including the recording preview. The button uses the theme's
primary/on-primary colors instead of a separate blue/white palette. A flexible
waveform stays within narrow messages; seeking still measures the wave itself.
The widget regression rejects overflow instead of draining it as an expected
test-font artifact.

## Conversation type cues

`ConversationKindStyle` owns the glyph and the localized type label.
`ConversationKindAvatar` shows a person's initials, or the group/channel glyph,
on the avatar plate picked from the name.

| Type | Glyph |
| --- | --- |
| Personal | The contact's initials on the avatar |
| Group | Participants |
| Channel | `#` |

Since MOSH-134 the type has no colour of its own: the open chat is the one
`secondaryContainer` row for every type, and a lit filter is the same fill.
The filters name the types in words. Glyphs, localized tooltip/type labels
and channel-name prefixes communicate the type. Runtime protection indicators
continue to read actual snapshots.

## Initial consistency verification

- `flutter analyze --no-pub`: no issues.
- Full widget/unit suite with branch coverage: 989 passed, 5 skipped by the
  existing native-library gates, four requiring Windows DLLs and one libmpv.
- Changed executable lines: 75/75; changed branches: 23/23. Static geometry and
  color constants are not executable lines in LCOV.
- Desktop and mobile screenshots were inspected; all three kinds pass layout
  checks at 320, 390, 581, 800, 1280 and 1536px. Voice controls are also checked
  within a 224px message, including the centered 40px play target.
- Changed Dart files are formatted and `git diff --check` is clean.
- Windows rendering, native recording and playback require device evaluation.

Current bubble/header verification is recorded in the follow-up document.

Existing declarative theme/composer/rail widget trees and screenshot fixture
builders exceed the 50-line function limit. Their existing boundaries stay
together; new shape tokens and kind presentation are separate small modules.
The existing 469-line `sessions_screen_test.dart` retains its established suite;
this follow-up changes only the accessible-name expectation and test title.

## Changed files

- App: `lib/src/app/mosh_shapes.dart`, `lib/src/app/mosh_theme.dart`.
- Conversation: `attachment_card.dart`, `attachment_card_branches.dart`,
  `attachment_thumb.dart`, `channel_screen.dart`, `conversation_app_bar.dart`,
  `conversation_composer.dart`, `conversation_date_divider.dart`,
  `conversation_details_panel.dart`, `conversation_message_row.dart`,
  `conversation_search_box.dart`, `conversation_shared_file.dart`,
  `group_screen_header.dart`, `voice_message_card.dart`, all under
  `lib/src/features/conversation/`.
- Sessions: `rail_entry.dart`, `rail_item.dart`, `sessions_list_controls.dart`,
  under `lib/src/features/sessions/`.
- Shared: `conversation_kind_style.dart`, `voice_composer.dart`, under
  `lib/src/features/shared/`.
- Localization: `lib/l10n/app_en.arb`, `lib/l10n/app_ru.arb`.
- Tests: `test/features/conversation/voice_message_layout_test.dart`,
  `test/features/conversation/voice_message_card_test.dart`,
  `test/features/routing/chat_redesign_layout_test.dart`,
  `test/features/sessions/sessions_screen_test.dart`.
- Documentation: this file, `docs/Features/chat-redesign.md`,
  `docs/Architecture.md`.
