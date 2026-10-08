# Ordinary dialogs

Mosh's confirmations, rename forms, sender actions, encryption fingerprints and
setup restart notice share `MoshDialog` and `showMoshDialog`. VPN consent also
uses the shared shell and motion while retaining its existing overlay owner.
Voice-call windows,
full-screen media and conversation detail sheets keep their own layouts.

The user stays in the current chat while making one decision. The title shares
its header with a 40px close target. Content follows beneath it; actions sit at
the lower right and wrap vertically when space is tight. The card is at most
420px wide with 16px outer clearance, 22px content insets and 14px corners.
Scrollable content accommodates narrow windows, larger text and the keyboard.

The shell uses the existing Mosh theme: raised `surfaceContainerHigh`, a quiet
outline, primary title text and secondary body text. Titles use 16px semibold
type, body copy 13.5px with 1.5 line height. Moss continues to identify the
primary action. Danger color belongs on destructive actions; confirmations
have no decorative warning banner. Unnamed DM/group confirmations use localized
generic titles instead of technical session/group IDs.

Backdrop, Escape, system back, close and Cancel use the same cancellation path.
Only an explicit destructive action confirms. A rename cancellation discards
unsaved input without another prompt. During an admitted rename write,
cancellation and resubmission stay disabled until the write returns, preserving
the existing operation semantics. Errors retain the entered name for retry.

Flutter owns modal semantics, safe-area placement, closed-loop focus traversal,
focus restoration and inherited themes. The shell reuses `AlertDialog` and the
existing `ModalFocusTrap`, while feature callers retain their actions and typed
results. Destructive actions do not receive initial focus.

The motion follows [the selected transitions.dev modal reference](https://github.com/Jakubantalik/transitions.dev/blob/main/skills/transitions-dev/06-modal.md):
250ms open, 150ms close, center scale 0.96 to 1 and opacity 0 to 1, with
`cubic-bezier(0.22, 1, 0.36, 1)` for each direction. Close reverses the scale and
opacity. `MediaQuery.disableAnimations` removes the route transition entirely.
The custom route only adapts motion; Flutter's `DialogRoute` owns modal behavior.
VPN consent sits above the router, so `AnimatedSwitcher` owns its entrance and
exit using the same `MoshDialogMotion` values and `MoshDialogTransition`.
Its backdrop, Escape and close controls call the existing decline command;
only the explicit consent button can enable VPN bypass.

Focused widget checks cover explicit confirmation, every dismissal path,
unsaved rename cancellation, disabled destructive permissions, narrow layouts,
focus trapping/restoration and reduced motion. The declarative shared dialog
build composes Flutter's existing dialog controls; it may exceed the 50-line
function budget after formatting to keep that layout together.
