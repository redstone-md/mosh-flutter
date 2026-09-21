// Shared ConfirmDialog -- the 1-1 port of React's
// `src/features/private-dm/ConfirmDialog.tsx`. A centered modal
// confirmation dialog used by destructive-action flows. Rendered via
// Flutter's `showDialog`, which provides the modal barrier + focus trap
// natively. Cancel only happens via the Cancel button, the close-X, or
// Esc -- a stray scrim tap is a NO-OP: `showDialog` is
// `barrierDismissible: false`, matching React's `role="presentation"`
// backdrop with no `onClick`. Esc is wired through a `KeyboardListener`
// (the same pattern the call modals + `PeerStatusDrawer` use for the
// `useModalFocus` Esc-trap), and Android system-back cancels via
// `PopScope(canPop: false, onPopInvokedWithResult:)` (back=cancel).
//
// This atomic is JUST the widget + the `showConfirmDialog` helper -- NOT
// the close-flow wiring (that is a later atomic that passes `title` /
// `body` / `confirmLabel` from its own ARB keys and calls `onCancel` /
// `onConfirm`).
//
// Flutter element mapping (React -> Flutter):
//   `confirm-dialog-backdrop` -> `showDialog` modal barrier (scrim no-op
//     via `barrierDismissible: false`).
//   `confirm-dialog` card -> `Dialog`-shaped card, close-X in the top-
//     right corner, alert icon in a tinted rounded square
//     (`.confirm-dialog-icon`), h2 title + p body (muted), actions row of
//     ghost TextButton (cancel) + danger FilledButton (confirm). The
//     danger color is React's `--danger` `#e86a5a` -
//     `Color(0xFFE86A5A)`, overridable via the `dangerColor` prop.
//   `role=dialog aria-modal aria-labelledby` -> `Semantics(container:
//     true, label: title)` (the `showDialog` host already provides modal
//     route scoping).
//   close-X `aria-label=cancelLabel` -> `tooltip` + semantics label.
//   alert icon `aria-hidden` -> `excludeSemantics: true`.
//   Initial focus on the close-X -> Flutter's `Dialog` autofocuses the
//     first focusable child, mirroring `useModalFocus` focusing element
//     [0] -- the SAFE default for a destructive dialog (an accidental
//     Enter dismisses, it does not confirm).
library;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:flutter/services.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';

/// A centered modal confirmation dialog -- 1-в-1 with React's
/// `ConfirmDialog`. Construct directly and pass to `showDialog`, or use
/// the [showConfirmDialog] helper which returns `true` if the user
/// confirmed, `false` (or null) if they cancelled.
///
/// Mirrors React's prop shape exactly:
/// - `title`        -> h2 (`confirm-dialog-title`)
/// - `body`         -> p  (`confirm-dialog-body`)
/// - `confirmLabel` -> the danger button text
/// - `cancelLabel`  -> the ghost button text + the close-X aria-label
///   (React default `"Cancel"`; here defaults to [defaultCancelLabel] when
///   null so callers without a localized "Cancel" still get a sane label)
/// - `onCancel`     -> invoked on close-X, ghost button, or Esc /
///   Android system-back (the host wires scrim-no-op through
///   [showConfirmDialog])
/// - `onConfirm`    -> invoked on the danger button
///
/// The widget is a [StatefulWidget] only because it owns the `FocusNode`
/// the `KeyboardListener` (Esc -> `onCancel`) attaches to -- mirroring the
/// call modals' + `PeerStatusDrawer`'s `useModalFocus` Esc-trap pattern.
/// The card itself is pure; [build] delegates to [_ConfirmDialogCard].
class ConfirmDialog extends StatefulWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.cancelLabel,
    required this.onCancel,
    required this.onConfirm,
    this.dangerColor = MoshColors.danger,
  });

  /// The dialog title (React `title` -> `<h2 id="confirm-dialog-title">`).
  final String title;

  /// The dialog body (React `body` -> `<p id="confirm-dialog-body">`).
  final String body;

  /// The danger (confirm) button label (React `confirmLabel`).
  final String confirmLabel;

  /// The ghost (cancel) button label AND the close-X aria-label (React
  /// `cancelLabel`, default `"Cancel"`). Falls back to
  /// [defaultCancelLabel] when null so the dialog always has a cancel
  /// affordance; callers pass a localized label from their ARB key.
  final String? cancelLabel;

  /// Invoked when the user cancels (close-X, ghost button, or
  /// barrier/Esc dismiss via [showConfirmDialog]).
  final VoidCallback onCancel;

  /// Invoked when the user confirms (danger button).
  final VoidCallback onConfirm;

  /// Danger accent color -- React's `--danger` `#e86a5a` by default
  /// (`Color(0xFFE86A5A)`). Drives the alert-icon tint + the confirm
  /// button background. Overridable for tests + theming.
  final Color dangerColor;

  /// Default cancel label used when [cancelLabel] is null. Matches React's
  /// inline default `"Cancel"`; the close-flow atomic will pass a
  /// localized label instead.
  static const String defaultCancelLabel = 'Cancel';

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  // React `useModalFocus` keeps a single focus target for the modal; the
  // Flutter equivalent is a [FocusNode] owned here and attached to a
  // [KeyboardListener] wrapping the card. `autofocus: true` pulls focus
  // into the dialog on mount (React `first.focus()`), and the key handler
  // forwards Esc to `onCancel` (React `onKeyDown` Escape branch). The call
  // modals (`IncomingCallModal` / `OutgoingCallModal`) +
  // `PeerStatusDrawer` use the same `KeyboardListener`-Esc pattern; this
  // dialog matches them.
  late final FocusNode _focusNode = FocusNode(debugLabel: 'ConfirmDialog');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The `KeyboardListener` is the outermost node so Esc is caught before
    // any child focusables; `autofocus: true` pulls focus into the dialog on
    // open (React `first.focus()`). The `PopScope` gates Android
    // system-back: `canPop: false` blocks the default pop (the scrim is
    // already a no-op via `barrierDismissible: false`), and
    // `onPopInvokedWithResult` fires `onCancel` when a back press is
    // attempted -- Esc/back parity so the user is never trapped in a
    // destructive confirm with no escape. React web has no back button, but
    // on Android the expectation for a modal is back=cancel.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        widget.onCancel();
      },
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (event) {
          // React: `if (event.key === 'Escape') { stopPropagation();
          // onEscape(); }` -> `useModalFocus(onCancel)`. `KeyDownEvent`
          // only -- not `KeyRepeatEvent`/`KeyUpEvent` -- so a held Esc does
          // not fire `onCancel` repeatedly (matches the call modals).
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onCancel();
          }
        },
        // ModalFocusTrap goes inside KeyboardListener so Escape is caught first by the
        // outer KeyboardListener, while Tab key events are handled by the trap.
        child: ModalFocusTrap(
          child: _ConfirmDialogCard(
            title: widget.title,
            body: widget.body,
            confirmLabel: widget.confirmLabel,
            cancelLabel: widget.cancelLabel,
            onCancel: widget.onCancel,
            onConfirm: widget.onConfirm,
            dangerColor: widget.dangerColor,
          ),
        ),
      ),
    );
  }
}

/// The pure card body of [ConfirmDialog], factored out so the
/// `StatefulWidget`'s `build` stays focused on the Esc/back wiring.
/// Mirrors React's `confirm-dialog` element.
class _ConfirmDialogCard extends StatelessWidget {
  const _ConfirmDialogCard({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onCancel,
    required this.onConfirm,
    required this.dangerColor,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String? cancelLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final Color dangerColor;

  @override
  Widget build(BuildContext context) {
    final cancel = cancelLabel ?? ConfirmDialog.defaultCancelLabel;
    return Semantics(
      label: title,
      container: true,
      // `showDialog` already creates a `ModalRoute` the assistive layer
      // treats as a modal route boundary (the Flutter equivalent of React's
      // `aria-modal="true"` + `useModalFocus` route scoping). We do NOT set
      // `scopesRoute: true` here: that requires `explicitChildNodes: true`
      // (framework assertion) AND duplicates the modal-route scoping the
      // `showDialog` host already provides. Keeping `container: true,
      // label: title` gives the labeled-group announcement (React's
      // `aria-labelledby="confirm-dialog-title"`).
      child: Dialog(
        // React `width: min(100%, 380px)`. Material `Dialog` clamps by
        // `Dialog` constraints; cap at 380 so wide screens do not stretch
        // the card. `insetPadding` mirrors React's `padding: 24px` on the
        // backdrop.
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        // `.confirm-dialog { border: 1px solid var(--line-strong) }` -- the
        // call cards carry no border, so this sits on the dialog rather
        // than in the shared dialogTheme.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: MoshColors.lineStrong),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            // React `padding: 22px; gap: 16px`.
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // React `.confirm-dialog-close` sits in the top-right
                // corner (absolute). Flutter port: render it as a real
                // header Row right-aligned at the top of the card so it is
                // robustly hit-testable (a `Stack + Positioned` with a
                // negative offset places the IconButton outside the
                // dialog's clip/hit-test bounds and is flaky under tests +
                // mouse). The visual result matches React -- a small X in
                // the top-right corner -- and the title's leading margin
                // stays clear of it.
                Align(
                  alignment: Alignment.topRight,
                  child: _CloseButton(tooltip: cancel, onPressed: onCancel),
                ),
                // React `.confirm-dialog-icon` (IconAlertTriangle,
                // aria-hidden) in a 38x38 tinted rounded square.
                _AlertIcon(dangerColor: dangerColor),
                const SizedBox(height: 16),
                // React `.confirm-dialog-copy`: h2 title + p body.
                // `.confirm-dialog-copy h2 { font-size: 16px; line-height:
                // 1.25; color: var(--fg-1) }`.
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: MoshColors.fg1,
                  ),
                  textAlign: TextAlign.left,
                ),
                const SizedBox(height: 8),
                // `.confirm-dialog-copy p { color: var(--fg-2); font-size:
                // 12.5px; line-height: 1.55 }`.
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: MoshColors.fg2,
                    height: 1.55,
                  ),
                  textAlign: TextAlign.left,
                ),
                const SizedBox(height: 16),
                // React `.confirm-dialog-actions`: ghost Cancel +
                // danger Confirm, right-aligned.
                // React `.confirm-dialog-actions` is `display:flex;
                // justify-content:flex-end; gap:8px` with no explicit
                // flex-wrap on desktop (it relies on the 380px cap being
                // wide enough). The Flutter port renders under the wider
                // Ahem test font, where the close-flow's longer labels
                // ("Cancel" + "Leave channel") overflow a fixed `Row`.
                // `Wrap` with `alignment: end` + `spacing: 8` reproduces
                // the right-aligned single-line layout when the buttons
                // fit (visually identical to React's flex row) and degrades
                // to a wrapped stack when they don't -- mirroring React's
                // `@media (max-width:480px) { flex-direction:column-reverse;
                // width:100% }` fallback for narrow surfaces.
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    // React `btn btn-ghost` -> Material TextButton (no
                    // background, primary-foreground text).
                    TextButton(onPressed: onCancel, child: Text(cancel)),
                    // React `btn btn-danger` -> Material FilledButton with
                    // the danger background. No `autofocus` -- the close-X gets
                    // initial focus (see file header); confirm requires an
                    // explicit Tab/click so an accidental Enter can't trigger the
                    // destructive action.
                    FilledButton(
                      onPressed: onConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: dangerColor,
                        // Danger is a light fill: the theme's dark on-accent
                        // ink, not white (white reads at ~3.1:1 -- audit
                        // 2026-09-21; same mapping as onSecondary/onTertiary).
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The close-X button -- React `.confirm-dialog-close` (IconX size=16,
/// aria-label=cancelLabel). A 28x28 transparent square button with a
/// `Icons.close` icon + a tooltip/semantics label of the cancel label.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.close, size: 16),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      // React 28x28; compact splash to match the tight 28px hit area.
      splashRadius: 16,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
    );
  }
}

/// The alert icon -- React `.confirm-dialog-icon` (IconAlertTriangle size=18,
/// aria-hidden) in a 38x38 rounded tinted square. `excludeSemantics` mirrors
/// React's `aria-hidden="true"` (the icon is decorative; the title/body
/// carry the meaning).
class _AlertIcon extends StatelessWidget {
  const _AlertIcon({required this.dangerColor});

  final Color dangerColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // React `background: rgba(232, 106, 90, 0.12)` -- a 12% tint of
          // the danger color.
          color: dangerColor.withValues(alpha: 0.12),
          // React `border-radius: 10px`.
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          // React `IconAlertTriangle` (tabler). Material's `Icons.warning`
          // is the standard filled alert-triangle glyph; closest to lucide.
          Icons.warning,
          size: 18,
          color: dangerColor,
        ),
      ),
    );
  }
}

/// Shows a [ConfirmDialog] modally and returns `true` if the user
/// confirmed, `false` if they cancelled (close-X, ghost button, or Esc /
/// Android system-back). Mirrors the React close-flow's
/// `closeFlow.confirmCloseActive` / `closeFlow.cancelClose` seam so the
/// later close-flow atomic can wire its callbacks with a single
/// `await showConfirmDialog(...)` call.
///
/// The dialog is `barrierDismissible: false` -- a scrim tap is a NO-OP
/// (React's `role="presentation"` backdrop has no `onClick`), so a stray
/// tap on Android cannot silently cancel a destructive confirm. The dim
/// `barrierColor` still shows (the scrim is visible, just not dismissible).
/// Esc (via the `KeyboardListener`) and Android system-back (via the
/// `PopScope`) both cancel, matching React's `useModalFocus(onCancel)` Esc
/// branch + the Android back=cancel modal expectation. `barrierLabel` is
/// the [cancelLabel] (or [ConfirmDialog.defaultCancelLabel]) so the modal
/// scrim announces itself as a cancel affordance to assistive tech.
///
/// Returns `bool?` so the caller can distinguish null (dismissed without a
/// button tap) if needed; the convenience maps cancel/dismiss to `false`.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String confirmLabel,
  String? cancelLabel,
}) async {
  final cancel = cancelLabel ?? ConfirmDialog.defaultCancelLabel;
  final result = await showDialog<bool>(
    context: context,
    // React: the backdrop is `role="presentation"` with NO `onClick`, so a
    // scrim tap is a no-op (the dim scrim still shows via `barrierColor`).
    barrierDismissible: false,
    barrierLabel: cancel,
    builder: (dialogContext) => ConfirmDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancel,
      onCancel: () => Navigator.of(dialogContext).pop(false),
      onConfirm: () => Navigator.of(dialogContext).pop(true),
    ),
  );
  return result ?? false;
}
