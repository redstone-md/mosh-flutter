# Toasts

IVO-30 replaces per-Scaffold snackbars with one toast stack for the whole
app. On the desktop split the chat list and the chat were two Scaffolds, so
one copy showed the same snackbar in both.

## Behavior

- **Where.** On desktop the stack hangs centered below the titlebar, clear of
  the composer and the send button. On phones it sits above the composer.
  Toasts are 360px wide at most and never block taps around them.
- **What.** Copy confirmations, failed actions (accepting or dismissing an
  invitation, organization actions, starting or running a call, deleting
  messages, opening or picking an attachment, voice messages, hiding a notice),
  the device-link copy and copying a start menu invite report as toasts.
  Persistent banners, delivery states and inline form errors keep their own
  display.
- **Stacking.** The newest toast leads and up to two fold behind it, showing
  only their edge. A burst waits for a slot instead of evicting a toast
  before its text was exposed for 1.5s. Folded, unread toasts keep their
  lifetime until they reach the front or the pointer expands the stack.
  Repeating a shown message brings it back to the front with a short pop
  instead of stacking a copy.
- **Closing.** Confirmations last 4s, errors 6s. Hovering fans the stack out
  and holds dismissal timers; leaving grants each a full lifetime again. The close
  button and a swipe toward the edge dismiss at once.
- **Accessibility.** Each arrival and each repeat is announced; errors
  interrupt, confirmations wait. Each toast and its close button ("Dismiss
  notification") are separate semantics nodes.
- **Motion.** The values follow transitions.dev's toast and banner-stacking
  recipes and polish rules: 350ms in, 250ms out, 250ms fan out and 350ms
  collapse on `cubic-bezier(0.22, 1, 0.36, 1)`. A toast arrives from 16px
  toward the edge with a 2px blur at 0.97 scale. Folded toasts step back by
  12px, 6% scale and 40% opacity with 1–2px blur. Only a repeat overshoots.
  Under reduced motion toasts swap in place without travel or blur.

## Ownership

`Toaster` (`features/shared/toasts/toaster.dart`) owns the stack, the queue
and the timers; `toasterProvider` holds the app's one instance. `ToastHost`
renders it from `MaterialApp.builder`, above the first-run gate and the call
strip, and `ToastLayout` computes each toast's pose. `ToastMotion` holds the
motion values.

Callers read `context.toaster` before their first `await` and show
afterwards, so a result that lands after its screen closed still reports
without touching a disposed context. `actionErrorReporter` does the same for
`ConversationActionError` wording.

## Checks

- `toaster_test.dart` covers bursts, repeats, lifetimes, pausing and
  dismissal.
- `toast_host_test.dart` covers rendering, announcements, the close button,
  swipes, hovering, taps around the stack, phones, reduced motion and
  disposal.
- `app_toasts_test.dart` covers the desktop copy and a deletion failing after
  its chat closed.
- `toast_motion_preview_test.dart` renders the motion frame by frame with
  `--dart-define=TOAST_PREVIEW=<dir>` for visual review and checks that
  captured frames release their native images.

Real-device motion and screen reader output remain runtime checks.
