# Chat list layout

IVO-29 (IVO-12, IVO-15, IVO-16) makes the desktop chat list resizable and
collapsible and evens out its insets. Phones keep the existing list and
navigation.

## Behavior

- **Resizing.** The divider between the list and the conversation is a 9px
  handle with a resize cursor. Its line lights up on hover, focus and drag.
  The list follows the pointer from the press. Its width stays between 268px
  and 480px, and the conversation keeps at least 320px. Without a chosen
  width the list takes 28% of the window, capped at 348px.
- **Collapsing.** A drag below the midpoint between the narrowest list and the
  strip collapses the list to an 80px avatar strip. A drag out of the strip
  expands it again. The titlebar button, a double click on the handle and
  Enter or Space on the focused handle toggle it too. Collapsing and expanding
  animate for 200ms unless the system reduces motion. Resizes follow at once.
- **Keyboard and screen readers.** The handle is in the focus order. Arrow keys
  resize it in 16px steps; Left at the narrowest width collapses it and Right
  expands the strip. Screen readers get a slider named "Chat list width"
  with increase and decrease actions and a collapse or expand action.
- **The strip.** It shows New chat, Search and Settings as 48px icon
  buttons, one 64px avatar row per conversation with its unread badge on the
  corner, and organization avatars. Names appear in
  tooltips and screen readers read the full row. Conversation avatars open
  their chat. Invitations and organizations expand the list instead of acting,
  so a click on an avatar never accepts anything. Search and Ctrl/Cmd+K expand
  the list and focus its search. A failed load shows a retry button.
- **What survives.** Collapsing keeps the search text, the kind filter, the
  open chat, its draft and the list scroll.
- **Persistence.** The chosen width and collapsed state are saved to
  `chat-list-layout` in the app data directory once a drag ends. Missing or
  malformed data means the default layout. A failed save is logged and only
  loses the choice on the next launch. Phones ignore it.
- **Insets.** List rows, the pinned New chat and Settings buttons and the search
  field sit 8px from both edges and 16px from the top and bottom, with 8px
  between them; a row keeps its content 12px inside its own edge. The list
  scrollbar runs in the right gutter. Filter chips line up with the search
  field. The clip leaves room for their focus ring.
- **Rows.** MOSH-134 draws the list from the Chat row, Chat list and
  Organisation cards of the Components page. A row is 64px with 16px corners:
  the name and the time over the last message and the unread count. The open
  chat is the one `secondaryContainer` row, whatever its type; hover, press
  and focus are `MoshState` layers, and a row stays pressed under its open
  menu. An invitation offers its two answers as buttons in the row.
- **Search.** The field is a pill with a clear button while it holds a query.
  It looks through chat names, participants and the text of the messages
  loaded on this device. An empty list, an empty search and a failed load each
  show a notice in place of the rows; a failed load offers to try again.
- **Returning from settings.** Rail buttons and rows remount their ink when a
  covering route or an offstage phone branch resumes their tickers, so the
  press ink frozen under settings does not finish fading after Back.

## Ownership

`RailLayoutNotifier` (`state/rail_layout_provider.dart`) holds the layout:
drag steps preview it, and drag ends, toggles and key steps save it.
`RailPane` (`routing/rail_pane.dart`) lays out the list, the divider and
the handle. The list is laid out at its final width and clipped while the
width animates, so it never reflows mid-animation. `RailCompactScope` tells the
rail widgets whether to render the strip. `CompactRailItem` renders a
`RailItem` in the strip, so rail entries need no strip-specific code.

## Checks

- `rail_pane_test.dart` covers widths, dragging, snapping, the titlebar
  button, the animation, reduced motion, keyboard, double click, slider
  semantics, restarts, phones, Ctrl+K and preserved state.
- `rail_compact_test.dart` covers strip rows, invitations, organizations,
  failed loads, the empty state and Settings.
- `rail_item_test.dart` covers the row's contrast in both palettes, its
  selected and menu-open states, large text and the truncation tooltip;
  `search_field_test.dart` the field's clear button and its quiet inks;
  `recent_chats_test.dart` the search, message text included.
- `preferences_test.dart` (group `rail_layout`) covers storage.
- `rail_insets_test.dart` covers insets.
- `rail_settings_button_return_test.dart` covers the press ink.

Physical mouse, trackpad and window resizing remain runtime checks.
