# Ordinary dialogs

Mosh's confirmations, rename forms, sender actions, encryption fingerprints and
setup restart notice share `MoshDialog` and `showMoshDialog`. VPN consent also
uses the shared shell and motion while retaining its existing overlay owner.
Call views,
full-screen media and conversation detail sheets keep their own layouts.

The user stays in the current chat while making one decision. The dialog
follows the Dialog card of the Components page: a surface of the modal level
(`MoshLevel.modal`: `surfaceContainerHigh`, an `outlineVariant` edge, 28px
corners, the level 3 shadow) on the scrim, at most 400px wide with 24px insets
and 16px between its parts. The title is `titleLarge`, the body `bodyMedium` in
`onSurfaceVariant`. The answers sit at the lower right, the one that goes on
last; answers that do not fit the line stack with the main one on top, and the
VPN consent's long answers always stack at full width on a phone. A destructive
answer is the only red on a dialog: the `error` fill with `onError` ink.
Cancel, Escape and a press on the scrim all leave without a change, so only a
dialog without answers of its own (call devices, the fingerprint) has a close
button. Unnamed DM/group confirmations use localized generic titles instead of
technical session/group IDs.

The scrim under every modal is `surfaceContainerLowest` at the `state/scrim`
opacity (`MoshColors.scrim`): dialogs, the VPN consent and the phone's sheet.

Backdrop, Escape, system back, the close button and Cancel use the same
cancellation path.
Only an explicit destructive action confirms. A rename cancellation discards
unsaved input without another prompt. During an admitted rename write,
cancellation and resubmission stay disabled until the write returns, preserving
the existing operation semantics. Errors retain the entered name for retry.

Flutter owns modal semantics, safe-area placement, closed-loop focus traversal,
focus restoration and inherited themes. The shell reuses `Dialog` and the
existing `ModalFocusTrap`, while feature callers retain their actions and typed
results. Destructive actions do not receive initial focus.

The motion follows [the selected transitions.dev modal reference](https://github.com/Jakubantalik/transitions.dev/blob/main/skills/transitions-dev/06-modal.md):
250ms open, 150ms close, center scale 0.96 to 1 and opacity 0 to 1, with
`cubic-bezier(0.22, 1, 0.36, 1)` for each direction. Close reverses the scale and
opacity. `MediaQuery.disableAnimations` removes the route transition entirely.
The custom route only adapts motion; Flutter's `DialogRoute` owns modal behavior.
VPN consent sits above the router, so `AnimatedSwitcher` owns its entrance and
exit using the same `MoshDialogMotion` values and `MoshDialogTransition`.
Its backdrop, Escape and "Keep using the VPN" call the existing decline command;
only the explicit consent button can enable VPN bypass. While the answer is
saved that button keeps its colours and spins.

Focused widget checks cover explicit confirmation, every dismissal path,
unsaved rename cancellation, disabled destructive permissions, narrow layouts,
focus trapping/restoration and reduced motion. The declarative shared dialog
build composes Flutter's existing dialog controls; it may exceed the 50-line
function budget after formatting to keep that layout together.
