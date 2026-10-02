# Message bubbles and conversation header

## Approved scope

The user approved this follow-up on 2026-10-01 after reviewing the first chat
redesign. Preserve the existing dark Mosh palette, Material widgets, routes,
runtime states, and conversation type cues. Evolve the shared conversation UI.
`DESIGN_VARIANCE=4`, `MOTION_INTENSITY=2`, `VISUAL_DENSITY=5`: restrained
geometry, existing feedback, daily messaging density.

The audit found tight 8px bubble insets, a separate time row even for short
text, repeated contact names in DMs, and a header with inconsistent action
order and duplicate admin/invitation controls. The fingerprint's 41px target
inside the name row also separates the name and subtitle unnecessarily.

## Plan and boundaries

1. Use existing five-minute, same-sender, same-day grouping in both directions
   to connect bubble corners. Keep a 16px outside corner and 4px joins on the
   sender's side, with 12px horizontal/10px vertical insets and 4px/12px gaps.
2. Measure actual text lines and time with Flutter's text scaling, font and
   locale. Place time beside the last line when space allows, otherwise below.
   Keep the body an ordinary selectable `Text`; attachments keep a footer.
   The shared measurement helper mirrors `Text`'s bold/line-height/letter/word
   spacing accessibility overrides as well as locale and text scaling.
3. Compose a compact header identity, preserving the fingerprint as its own
   24px action beside the nickname. Clicking the identity opens
   existing details. Order actions call, search, menu; keep invitation copy in
   the menu and admin role once.
4. Verify text/timestamp separation, grouping, selection/copy, keyboard and
   fingerprint/details actions, invitation copying, and all three kinds across
   existing responsive widths. Run analysis, relevant/full Flutter tests and
   changed-code coverage, then commit and push the existing branch.

Main risks: text measurement diverging from actual rendering, footer overlap
at larger text sizes, and nested identity/fingerprint gestures. Reuse the
same effective text style/scaler in measurement and rendering and test these
caller-visible cases. No dependency, Rust, bridge, storage or schema change.

## Shape and contrast rules

- List rows retain 12px corners; text and voice messages use 16px outside
  corners and 4px directional joins. Composer 16px and controls 8px follow the
  documented role scale. File and media messages keep all four 16px bubble
  corners, with equal 8px insets and 8px inner corners. Preview captions leave
  the bottom inset to the bubble.
- Outgoing bubble surface is `#273D2D`, a subdued moss tint. Body text clears
  10.04:1, outgoing time clears 5.22:1, and incoming time clears 4.97:1.
  Normal outgoing delivery marks share its brighter secondary foreground;
  actual read receipts retain the existing accent and localized semantics.
- The group admin role appears once in its status line. The public-channel
  header explicitly labels the kind without implying encryption or membership.
- The nickname lock uses a 12px glyph and a 24px hover/tap target with 4px
  corners. Its glyph follows the name line; the name/details target stays 41px.
- DM rows use their header identity; group/channel sender names, fingerprint
  actions and protection labels remain on the first message of each block.

## Design pre-flight

Audit and preserve mode are recorded above. Existing typography and dark theme
stay in place; all new controls use existing Material glyphs and feedback.
The agreed three conversation-type accents remain semantic type cues. Runtime
statuses and read receipts remain actual values, and missing timestamps stay
missing. No new decorative motion, imagery, gradients or surfaces are added.
Marketing hero, CTA, bento, photography, SEO, React/CSS and dual-theme checks
are outside this native component scope. Responsive layout and keyboard,
selection, attachment, invitation and fingerprint behavior are verified below.

Existing declarative message-row/header widget trees and test fixture builders
exceed the three-level nesting/50-line function guidance. Their widget boundary
stays together; new footer, text metrics and title modules are below the type
and file limits. The group header and its fixture suite are substantially
smaller after removing duplicate invitation and admin controls.

## References

- Existing user reference: `../mosh-redesign/экран чата.png`.
- [Signal Desktop conversation header](https://github.com/signalapp/Signal-Desktop/blob/main/ts/components/conversation/ConversationHeader.dom.tsx):
  clickable identity and separate contextual actions.
- [Flutter TextPainter](https://api.flutter.dev/flutter/painting/TextPainter-class.html):
  actual paragraph line metrics, text scaling, and disposal of temporary painters.

The requested `design-taste-frontend` skill supplies audit, hierarchy, rhythm,
and shape discipline. Its web marketing, hero, image-generation and SEO rules
do not apply to this existing Flutter messenger.

## Verification

- Regression-first checks failed before the change for inline time, repeated
  DM names, bubble insets, header action order and clickable details identity.
- `flutter analyze --no-pub`: no issues.
- Full Flutter suite with branch coverage: **1005 passed, 5 skipped**. The skips
  are four existing Windows native-DLL gates and one unavailable libmpv probe.
- Changed executable-line coverage: **201/204 (98.5%)**; available changed
  branches: **33/33 (100%)**. Pure shape constants have no LCOV executable lines;
  rendered widget checks cover their geometry.
- Actual selection/copy preserves bodies without timestamp text or object
  placeholders. RTL, large text, accessibility spacing, missing timestamps,
  footer separation, keyboard activation and distinct fingerprint/details
  actions pass.
- DM/group/channel layouts pass at 320, 390, 581, 800, 1280 and 1536px. Final
  desktop/mobile screenshots for all three kinds were visually inspected with
  real DejaVu test fonts. Group invitation copying, acknowledgement/reset and
  admin role/member counts pass.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  414 files, no changes. `git diff --check` is clean.
- Windows rendering with the application's actual fonts and native audio still
  requires evaluation on the user's device. No Windows toolchain is available
  in this Linux workspace. The existing JNI cache workaround is unaffected.

## Changed files

- `docs/Architecture.md`
- `docs/Features/chat-message-header-polish.md`
- `docs/Features/chat-redesign.md`
- `docs/Features/chat-visual-consistency.md`
- `lib/src/app/mosh_shapes.dart`
- `lib/src/app/mosh_theme.dart`
- `lib/src/features/conversation/channel_screen.dart`
- `lib/src/features/conversation/chat_header_menu.dart`
- `lib/src/features/conversation/conversation_app_bar.dart`
- `lib/src/features/conversation/conversation_header_title.dart`
- `lib/src/features/conversation/conversation_helpers.dart`
- `lib/src/features/conversation/conversation_message_footer.dart`
- `lib/src/features/conversation/conversation_message_list_view.dart`
- `lib/src/features/conversation/conversation_message_row.dart`
- `lib/src/features/conversation/conversation_message_text.dart`
- `lib/src/features/conversation/conversation_sender_meta.dart`
- `lib/src/features/conversation/conversation_text_metrics.dart`
- `lib/src/features/conversation/dm_screen_header.dart`
- `lib/src/features/conversation/group_screen_header.dart`
- `lib/src/features/conversation/mobile_conversation_search.dart`
- `lib/src/features/fingerprint/fingerprint_lock.dart`
- `lib/src/features/sessions/rail_item.dart`
- `test/features/conversation/channel_screen_notice_test.dart`
- `test/features/conversation/conversation_banners_test.dart`
- `test/features/conversation/conversation_bubble_layout_test.dart`
- `test/features/conversation/conversation_grouping_test.dart`
- `test/features/conversation/conversation_header_layout_test.dart`
- `test/features/conversation/conversation_message_row_test.dart`
- `test/features/conversation/delivery_ticks_read_test.dart`
- `test/features/conversation/group_screen_header_test.dart`
- `test/features/conversation/message_copy_test.dart`
- `test/features/conversation/mls_badge_test.dart`
- `test/features/routing/chat_redesign_layout_test.dart`
