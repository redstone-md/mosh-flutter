# Chat visual consistency

## Scope and checks

The follow-up to the chat redesign addresses the user's reported corner-radius
drift, displaced voice play icon, and indistinguishable conversation types.

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
- Color world: the existing near-black canvas, graphite surfaces, off-white
  text, moss green, channel blue, and a muted lilac for groups.
- Signature: conversation type has the same glyph and accent in the list,
  filters, header and details, independently of runtime security indicators.
- Defaults corrected: inherited Material pill shapes, separately rounded
  cards inside messages, and identical green avatars for every type.
- Depth and surfaces: existing dark surface steps and subtle edges; no new
  shadows or decorative gradients.
- Typography: existing Mosh theme; message text stays at 14px, previews and
  metadata use the existing smaller steps and foreground levels.
- Spacing: 4px base, 8px message inset and composer control inset. The waveform
  takes the remaining space, while play retains its 40px hit target.

## Shape ownership

`lib/src/app/mosh_shapes.dart` defines the chat geometry. Components reference
these tokens instead of choosing their own corner radius.

| Element | Radius | Relationship |
| --- | ---: | --- |
| Search, settings, filters, standard buttons | 8px | One shape across states |
| Messages and conversation rows | 12px | Stable when selected or grouped |
| Composer control group | 16px | 8px control corner plus 8px inset |
| Embedded media and file icon surfaces | 4px | 12px message corner minus 8px inset |

The message-search segment uses its outer 8px corner minus its 3px inset.
Avatars and voice play remain circles because they are identity and transport
controls, rather than rectangular fields. Progress bars retain their small
end caps. Modal geometry remains owned by the existing modal components.

Search uses the theme's full field-border state recipe, avoiding a local
default border with a different radius from the focused and disabled borders.
The composer input stays borderless when disabled as well as when enabled.

## Embedded files and voice

Files use a flat row within the bubble instead of a second rounded card. Media
previews clip to the embedded radius; failed transfers keep the existing error
edge, label and action. Download, cancel, retry and open behavior is unchanged.

Voice uses the same message surface. Play/pause is centered without an extra
translation, including the recording preview. The button uses the theme's
primary/on-primary colors instead of a separate blue/white palette. A flexible
waveform stays within narrow messages; seeking still measures the wave itself.
The widget regression rejects overflow instead of draining it as an expected
test-font artifact.

## Conversation type cues

`ConversationKindStyle` owns the accent, tint, glyph and localized type label.
`ConversationKindAvatar` composes the existing personal initials avatar with a
small chat badge, or renders the group/channel glyph on a tinted circle.

| Type | Accent | Glyph |
| --- | --- | --- |
| Personal | Moss green | Chat bubble, with the contact's initials |
| Group | Muted lilac | Participants |
| Channel | Blue | `#` |

Selected rows and filters use the matching tint. Text remains neutral. Glyphs,
localized tooltip/type labels and channel-name prefixes communicate the type
without relying on color. These accents do not imply a connection or encryption
state; runtime protection indicators continue to read actual snapshots.

## Verification

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
