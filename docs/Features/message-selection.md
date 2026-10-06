# Message selection

IVO-25 replaces the checkbox column with Telegram-style selection. One mode
serves DMs, groups and channels.

## Behavior

- **Entering.** "Select message" in the row menu, or a mouse drag that leaves
  the message it started on, turns the mode on. The anchor and every message
  the drag passes are picked.
- **Header.** While the mode is on, the chat header is replaced by a bar of the
  same height: a filled "Delete N" button on the left, Cancel on the right.
  An open search row stays usable. Screen readers hear "Selected: N".
- **Rows.** Picked rows get a full-width tint from the theme's primary color
  and report the selected state to assistive technology. A tap anywhere on a
  row picks or unpicks it. Shift extends the pick from the last picked row.
  Attachments, voice notes, sender names and the row menu rest in this mode.
- **Dragging.** The anchor decides the action: a drag from an unpicked row picks
  the range, a drag from a picked row unpicks it. Moving back returns the rows
  the range left to their previous state, so a row never toggles twice. A drag
  past the list edge auto-scrolls and keeps picking under the still pointer.
  Release or cancellation stops the scroll.
- **Touch.** In the mode, a long press followed by a drag picks a range with the
  same rules and auto-scrolls near the list edges. Plain swipes still scroll.
  Outside the mode, touch gestures are unchanged.
- **Leaving.** Cancel, Escape, system back, a successful deletion, a chat switch,
  or unpicking the last message leaves the mode. A refused deletion keeps the selection.
- **Copy.** Ctrl/Cmd+C copies picked messages, oldest first, separated by a
  blank line, without names or times. Messages without text are skipped.
- **Visibility.** Search and the attachment filter narrow the pick to visible
  messages. Messages that disappear from the conversation leave it too.

Deletion semantics are unchanged: see [ADR 0040](../ADR/0040-message-deletion.md).

## Ownership

`MessageSelection` is the state model: the picked ids, the visible order, the
drag anchor and a generation that late deletion results compare against.
`MessageSelectionHost` owns it for one screen and swaps the header.
`SelectableMessageRow` keeps one widget shape in both modes, so entering the
mode never remounts rows or their attachment state.

Mouse drags reuse the native `SelectionArea` drag: once it leaves its message,
the text highlight turns transparent and is cleared on release, while the
native edge auto-scroll carries the pick. Touch drags use a list-level long
press, which beats the native one because it is deeper in the tree, and an
`EdgeDraggingAutoScroller` re-aimed at the pointer on every step.

## Trade-off

Text selection that spans several messages is gone: crossing a message boundary
now picks messages, as in Telegram Desktop. Copying several messages goes
through the picked-message copy instead.

## Checks

`message_selection_model_test.dart` covers the state model.
`message_selection_mode_test.dart` and `message_drag_selection_test.dart` cover
the screen: the header swap, tint, taps, Shift, Escape, copy, search narrowing,
mouse and touch drags, and auto-scroll start and stop.
`message_selection_switch_test.dart` covers chat switches during deletion.
Physical pointer, trackpad and touch behavior remains a runtime check.
