# IVO-24: message context menus

## Scope

Unify text, caption, attachment and deleted-message menus using the existing
Mosh menu surface and items. Keep the conversation's single selection area and
the existing action callbacks. No native API, persistence or dependency changes.

## Agreed behavior

- Position the menu at the pointer or touch, keeping it inside the visible window.
- Show separate copy-selected and copy-message actions; hide inapplicable actions.
- Keep selection on a secondary click within it. A secondary click elsewhere
  clears it and targets that message. Copy-message and deletion target that row.
- Copying preserves selection. Escape and outside dismissal clear it. Existing
  deletion and message-selection actions clear text selection before running.
- Double click selects a word. A timed third mouse click selects the entire
  message body, including explicit newlines. Keep cross-message drag selection.
- Use the same menu on mobile with native text selection handles.
- Reuse Mosh menu icons and styling; place destructive deletion last.
- Follow transitions.dev dropdown motion: 250ms opening, 150ms closing,
  scale 0.97 to 1 on open and 1 to 0.99 on close, with
  cubic-bezier(0.22, 1, 0.36, 1). Grow from the actual placement corner.
  Reduced motion disables transitions. Reopening reverses an unfinished close.
- Support the menu key / Shift+F10, arrow navigation, activation and Escape.

## Sequence

1. Add failing caller-visible selection and menu regression tests.
2. Introduce one feature-local menu owner and integrate existing message actions.
3. Customize paragraph selection through Flutter's selection delegate hooks.
4. Update feature documentation and translations, then verify and commit.

## Risks and checks

Focus entering an overlay must retain the source selection. Timed third clicks
must select the body rather than a paragraph or sender metadata. Deferred menu
callbacks must not act on removed rows or disposed conversations. Test edge
placement, mobile long press, keyboard use, controls under the menu, reversals,
reduced motion, and ordinary/cross-message selection. Run Flutter analysis, the
full widget suite, formatting, and changed-line/branch coverage.
