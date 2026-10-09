# Message selection

IVO-25 implements message selection for DMs, groups and channels. IVO-60 / #76
refines its appearance with circular selectors and responsive action placement.

## Behavior

- **Entering.** "Select message" in the row menu, or a mouse drag that leaves
  the message it started on, turns the mode on. The anchor and every message
  the drag passes are picked.
- **Header.** While the mode is on, the chat header is replaced by a bar of the
  same height. It always shows "Selected: N" and Cancel. Desktop actions are
  Copy and a destructive Delete button. An open search row stays usable.
  Screen readers hear count changes through a live region.
- **Rows.** Every selectable message shows an empty circular selector; selected
  messages show a filled circle with a checkmark. Circles sit on the right on
  desktop and on the left at the existing mobile breakpoint of 580 px.
  Only picked bubbles get a tint from the theme's primary color. Rows report
  their selected state and selectors their checked state to assistive technology.
  A tap anywhere on a row picks or unpicks it. Shift extends the pick from the
  last picked row.
  Attachments, voice notes, sender names and the row menu rest in this mode.
  Nested controls lose keyboard focus and cannot be activated by pointer or
  keyboard; the row itself retains its copy and Escape shortcuts.
- **Mobile actions.** At 580 px and below, Copy and Delete replace the composer
  at the bottom. The hidden composer stays mounted, preserving its draft and
  controls, and cannot receive focus. Cancel restores it. Actions can wrap for
  larger text or longer localized labels.
  Hiding the composer finishes microphone capture and keeps the recorded clip
  for review after Cancel. A pending permission grant cannot start hidden capture;
  a recording that finishes starting while hidden stops immediately. Desktop
  selection keeps recording controls visible and does not stop capture.
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
- **Copy.** The Copy button and Ctrl/Cmd+C copy picked messages, oldest first,
  separated by a blank line, without names or times. Messages without text are
  skipped; Copy is disabled when the selection has no text. Copy keeps the
  selection. Copy, Delete, Cancel and selectors are disabled during deletion.
- **Visibility.** Search and the attachment filter narrow the pick to visible
  messages. Messages that disappear from the conversation leave it too.

Deletion semantics are unchanged: see [ADR 0040](../ADR/0040-message-deletion.md).
Translation remains a separate task (#74); this refinement adds no forwarding
or sharing operations.

## Ownership

`MessageSelection` is the state model: the picked ids, the visible order, the
drag anchor and a generation that late deletion results compare against.
`MessageSelectionHost` owns it for one screen and swaps the header. One
`MessageSelectionActions` renders the same actions above or below the list;
both placements use the host's existing bulk deletion flow through the scope.
`MessageSelectionComposer` hides the composer with state-preserving visibility.
`VoiceComposer` observes Flutter's inherited visibility and finalizes capture
through its existing stop/review flow, without depending on selection state.
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
the screen: the header swap, circles, bubble tint, taps, Shift, Escape, copy,
mobile placement, draft retention, search narrowing,
mouse and touch drags, and auto-scroll start and stop.
`message_selection_controls_test.dart` covers selector accessibility, keyboard
activation, pending deletion and large localized text.
`message_selection_voice_test.dart` covers hidden capture, clip retention,
desktop controls and selection during permission or capture startup.
`message_selection_switch_test.dart` covers chat switches during deletion.
Physical pointer, trackpad and touch behavior remains a runtime check.

The existing `ConversationMessageRow` and `ConversationScreenBody` retain their
type and build-method budget exceptions: their complete bubble and screen
composition stays together. New selection controls stay within the normal
source budgets.
The existing `_VoiceComposerState` exceeds the type-size budget: capture,
finalization and its three control phases remain together under one recorder
owner. Visibility handling adds no second capture owner.
