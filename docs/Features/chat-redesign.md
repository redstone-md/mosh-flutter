# Conversation redesign

The approved [wireframe](../Proposals/chat-redesign-wireframe.html) guides the
Flutter chat list, messages and details for DMs, private groups and public channels.

## Implementation sequence

1. Build one recent list from existing per-kind snapshots, then add previews,
   local title/known-author search and kind filters.
2. Restyle the shared message row and composer while preserving selection,
   retry, attachment transfer, voice and call controls.
3. Share details content between a docked desktop column and the existing
   accessible modal. Verify responsive layouts and existing conversation flows.

## Behavior and ownership

- `RailActivity` scans each history once. Text and attachments determine the
  latest activity; blank control/call events do not reorder chats. Dated activity
  precedes undated activity; chats without content are last. Equal times use the
  conversation key for stable order. Timestamps are local and localized.
- Invitations remain a separate section above recent chats. Existing organization
  actions remain below. Search and kind selection live in `SessionsScreen`;
  Riverpod still owns server snapshots. Ctrl+K (Cmd+K on macOS) focuses list search,
  returning to the list first on mobile.
- Desktop keeps list and chat together above 580px. The list grows from 268px to
  348px. At window widths of at least 1280px, details occupy a 320px third column
  and open initially. The header information button toggles them. Smaller windows
  use the existing focus-trapped overlay, including Escape and focus restoration;
  mobile keeps one navigation pane. An explicit details choice survives resizing.
- Incoming bubbles are left aligned; outgoing bubbles are right aligned. Sender
  actions remain on incoming rows. Each dated message shows a time; adjacent
  messages across a local date boundary start a fresh sender block. DM delivery
  icons retain localized tooltips/semantics and real authenticated read status.
- Message search opens from the header. Closing it or changing conversations
  clears the query so a hidden search cannot suppress messages. The shared action menu exposes files,
  existing kind actions and the confirmed leave flow on desktop and mobile.
- Details consume the same snapshot as the chat. Protection reflects actual DM
  and group states, revocation and rejoin requirements. Public channels explicitly
  show their public-channel notice and known authors, with no invented roster or
  MLS protection. Groups show actual roster identities when available; unresolved
  identities remain shortened identifiers. Existing diagnostics expand on demand.
- Shared files are deduplicated by attachment ID and reuse `AttachmentActions` and
  controller callbacks for download, cancellation, retry and opening. Updating
  any conversation also refreshes its kind's list for current previews.

## Checks and limits

The follow-up [Chat visual consistency](chat-visual-consistency.md) records the
shared corner geometry, embedded attachment simplification and conversation
type cues requested after the first Windows evaluation.

Tests cover recency, filtering, known names, runtime protection, file actions,
details toggling and Escape, keyboard navigation, local date boundaries, bubble
alignment and existing send/leave/attachment behavior. Layout tests exercise all
three kinds at 320, 390, 581, 800, 1280 and 1536px.

`chat_redesign_layout_test.dart` optionally exports screenshots with
`--dart-define=MOSH_REDESIGN_SCREENSHOTS=/tmp/mosh-redesign-preview`.
`MOSH_REDESIGN_FONT` can name a local font for inspection; CI uses its normal
test fonts. These exports are not build artifacts shipped with the app.

Existing orchestration methods in `ConversationScreen`, `ConversationScreenBody`,
`ConversationComposer` and `SessionsScreen` exceed the 50-line function limit;
their declarative widget trees and screen-owned lifecycle remain together.
The existing state types in `ConversationScreen`, `ConversationScreenBody` and
`ConversationComposer` also exceed 200 lines. Feature models,
presentation helpers, list aggregation and diagnostics are separate modules.

Native transport, Rust APIs, dependencies and persisted schemas are unchanged.
Physical Windows/Android runtime verification remains separate from widget tests.

## Verification results

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --branch-coverage`: 986 passed, 5 skipped by existing
  native-library gates (four require Windows DLLs; one requires libmpv).
- Changed executable lines: 664/691 (96.1%); changed branches: 184/201 (91.5%).
  Counts intersect LCOV data with added/modified production Dart lines.
- Changed Dart files are formatted; `git diff --check` is clean.
- Desktop and mobile screenshots were inspected using the optional export.
- Physical Windows/Android transport, recording and playback were not exercised.

## Changed files

### `docs/`

- `Architecture.md`

### `docs/Features/`

- `chat-redesign.md`

### `lib/l10n/`

- `app_en.arb`
- `app_ru.arb`

### `lib/src/features/conversation/`

- `channel_screen.dart`
- `chat_header_menu.dart`
- `conversation_app_bar.dart`
- `conversation_composer.dart`
- `conversation_date_divider.dart`
- `conversation_details_model.dart`
- `conversation_details_panel.dart`
- `conversation_diagnostics_content.dart`
- `conversation_helpers.dart`
- `conversation_message_list_view.dart`
- `conversation_message_row.dart`
- `conversation_peer_status.dart`
- `conversation_screen.dart`
- `conversation_screen_body.dart`
- `conversation_search_row.dart`
- `conversation_sender_meta.dart`
- `conversation_shared_file.dart`
- `dm_screen_header.dart`
- `group_screen_header.dart`
- `peer_status_drawer.dart`

### `lib/src/features/sessions/`

- `rail_activity.dart`
- `rail_entry.dart`
- `rail_item.dart`
- `sessions_list_controls.dart`
- `sessions_rail_list.dart`
- `sessions_screen.dart`

### `lib/src/routing/`

- `mosh_shell.dart`

### `lib/src/state/`

- `conversation_providers.dart`

### `test/features/conversation/`

- `conversation_close_flow_test.dart`
- `conversation_details_test.dart`
- `conversation_filter_test.dart`
- `conversation_grouping_test.dart`
- `conversation_message_row_test.dart`
- `conversation_peer_status_test.dart`
- `delivery_ticks_read_test.dart`
- `dm_queued_message_test.dart`
- `dm_screen_mobile_breakpoint_test.dart`
- `group_leave_label_test.dart`

### `test/features/routing/`

- `chat_redesign_layout_test.dart`
- `mosh_shell_test.dart`

### `test/features/sessions/`

- `recent_chats_test.dart`

### `test/features/shared/`

- `conversation_action_error_test.dart`

### `test/state/`

- `conversation_providers_test.dart`

### `test/support/`

- `message_builders.dart`
