# Message context menus

Text, captions, attachments, call rows and deleted-message placeholders use one
menu in the Mosh theme. A secondary click or long press opens it at the pointer
or touch. The menu flips at window edges and stays inside safe areas and above
the software keyboard. Large text and tall menus retain scrollable actions.

## Actions and selection

- Copy selected text copies the current fragment, including a selection spanning
  multiple messages. Copy message copies only the targeted message's body.
- Native text actions such as Select all and Share remain available where Flutter
  supplies them. Message selection and deletion use the existing row callbacks
  and deletion-scope dialog. Inapplicable actions are omitted; deletion is last.
- A secondary click within the text selection retains it. A secondary click
  outside it clears it and targets that message.
- Copying retains text selection. Escape and outside dismissal clear it. Opening
  message selection or deletion clears text selection before invoking the action.
- Double mouse click selects a word. A timed third click selects all the text in
  the clicked body, including explicit newlines, without sender metadata or time.
  Ordinary drag selection still spans messages. This is a mouse gesture;
  touchscreen selection keeps Flutter's long press and draggable native handles.
- Focused messages accept the menu key or Shift+F10. Arrow keys move through the
  menu; Enter/Space activate an action and Escape dismisses it. Closing restores
  the source row's focus. Ctrl/Cmd+C preserves normal selection copying,
  including while the menu owns focus.
- A removed or replaced source row dismisses its menu. Scrolling closes it.
  Deferred actions do not invoke a disposed source or conversation.
- Message identity owns row state; conversation identity owns selection/menu
  state. Equal text cannot retarget an open menu after insertion or navigation.
- Long press on an attachment opens its menu even when the message has a
  caption. Long press on selectable text retains native selection and handles.

## Motion and ownership

The feature-local menu uses Flutter's `RawMenuAnchor` for overlay lifecycle and
the existing `MoshMenuItem`/`MoshMenuTheme` for controls and surfaces. One
`SelectionArea` retains native selection, including cross-message dragging. Row
selection delegates customize paragraph selection without replacing Flutter's
gesture recognizer. Menu focus remains under the selection's focus node.

Motion follows the [transitions.dev menu dropdown recipe](https://transitions.dev/library.html):
opening takes 250ms with scale 0.97 to 1; closing takes 150ms with scale 1 to 0.99.
Both fade and use cubic-bezier(0.22, 1, 0.36, 1). Growth starts at the actual
cursor-facing corner after placement. Reopening during closing preserves current
opacity and scale. The system's reduced-motion setting disables this transition.
After a completed close, the next opening starts at scale 0.97 again.

## Checks

Widget tests exercise actual clipboard output, body/caption selection in all
three conversation kinds, menu targeting, dismissal, source disposal, keyboard
navigation, mobile handle dragging, attachment controls, enlarged text and edge
placement. Full Flutter analysis and tests are required. Physical OS pointer and
touch behavior remains a separate runtime check.

The menu panel and message row use declarative widget trees that exceed the
three-level nesting guideline; their lifecycle and selection logic remain in
separate, bounded types. Test entry points register independent scenarios and
exceed the 50-line function guideline.

## Verification results

- Flutter analysis is clean; formatting checks 599 files without changes.
- The applicable full suite passes 1617 tests, with 4 existing native-library
  skips. The unmodified `media_kit_tracer_test.dart` fails separately in this
  headless environment because `Player.screenshot()` returns null; it is the
  only test excluded from the final full run.
- Menu, selection, clipboard and deletion checks pass, including regressions
  for all four review findings and native caption-handle dragging.
- Review fixes cover 34/34 changed production lines and 14/14 branches.
  Every changed module meets the repository's individual minimums.
- A real Flutter render with bundled Inter and Material icons was inspected.
  Physical Windows/macOS/Android/iOS runtime interaction was not exercised.
