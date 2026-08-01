// Shared ConfirmDialog -- the 1-в-1 port of React's
// `src/features/private-dm/ConfirmDialog.tsx`. A centered modal confirmation
// dialog used by destructive-action flows (the close-flow leave/delete chat
// confirmation is the first caller; later atomics reuse this primitive for
// any "are you sure" prompt). The dialog is rendered via Flutter's
// `showDialog`, which provides the modal barrier + focus trap natively
// (better than React's manual `useModalFocus` Esc-trap): `showDialog` with
// `barrierDismissible: true` dismisses on outside-tap + Esc by default, and
// Flutter's `FocusScope` handles the focus-cycle within the dialog.
//
// This atomic is JUST the widget + the `showConfirmDialog` helper -- NOT the
// close-flow wiring (that is a later atomic that will pass `title` / `body`
// / `confirmLabel` from its own ARB keys and call `onCancel` /
// `onConfirm`).
//
// React structure (ConfirmDialog.tsx):
//   confirm-dialog-backdrop (role=presentation)
//     -> confirm-dialog (role=dialog, aria-modal=true, aria-labelledby,
//        aria-describedby, tabIndex=-1) + useModalFocus(onCancel)
//        -> close button (IconX, aria-label=cancelLabel) in the corner
//        -> alert icon (IconAlertTriangle, aria-hidden) in a tinted square
//        -> copy: h2 title (confirm-dialog-title) + p body
//           (confirm-dialog-body)
//        -> actions: ghost Cancel btn (cancelLabel) + danger Confirm btn
//           (confirmLabel)
//
// Flutter port: `showDialog` provides the `confirm-dialog-backdrop` (modal
// barrier, dismiss-on-tap-outside + Esc). The dialog card mirrors
// `confirm-dialog`: a `Dialog`-shaped card with a Stack so the close-X can
// be absolutely positioned in the corner (React `position: absolute; top:
// 12px; right: 12px`), an alert icon in a tinted rounded square (React
// `.confirm-dialog-icon`), the title (h2 -> `titleMedium`, bold) + body (p
// -> `bodyMedium`, muted), and an actions row (ghost TextButton +
// danger-color FilledButton). The danger color is React's `--danger`
// `#e86a5a` -> `Color(0xFFE86A5A)`, exposed via the `dangerColor` prop so
// tests + theming can override it; the default is the React literal.
//
// Accessibility: the card is wrapped in `Semantics(container: true,
// scopesRoute: true, label: title)` so a screen reader announces the dialog
// as a modal route labeled by the title (mirrors React's
// `role=dialog aria-modal aria-labelledby=confirm-dialog-title`). The close
// button's `tooltip` + semantics label = `cancelLabel` (React's
// `aria-label={cancelLabel}`); the alert icon is `excludeSemantics: true`
// (React `aria-hidden="true"`). Initial focus lands on the close-X: Flutter's
// `Dialog` autofocuses the first focusable child via its `FocusScope`, and the
// close-X `IconButton` is first in the widget tree -- mirroring React's
// `useModalFocus` focusing `focusableElements(root)[0]` (the close-X, which
// dismisses on Enter -- the SAFE default for a destructive-action dialog; the
// confirm button must be an explicit Tab/click, not an accidental Enter).
library;

import 'package:flutter/material.dart';

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
/// - `onCancel`     -> invoked on close-X, ghost button, or barrier/Esc
///   dismiss (the host wires barrier/Esc through [showConfirmDialog])
/// - `onConfirm`    -> invoked on the danger button
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.cancelLabel,
    required this.onCancel,
    required this.onConfirm,
    this.dangerColor = const Color(0xFFE86A5A),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cancel = cancelLabel ?? defaultCancelLabel;
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
                  child: _CloseButton(
                    tooltip: cancel,
                    onPressed: onCancel,
                  ),
                ),
                // React `.confirm-dialog-icon` (IconAlertTriangle,
                // aria-hidden) in a 38x38 tinted rounded square.
                _AlertIcon(dangerColor: dangerColor),
                const SizedBox(height: 16),
                // React `.confirm-dialog-copy`: h2 title + p body.
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.left,
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    // React `.confirm-dialog-copy p` color `--fg-2` (muted).
                    color: theme.colorScheme.onSurfaceVariant,
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
                   TextButton(
                     onPressed: onCancel,
                     child: Text(cancel),
                   ),
                   // React `btn btn-danger` -> Material FilledButton with
                   // the danger background. No `autofocus` -- the close-X gets
                   // initial focus (see file header); confirm requires an
                   // explicit Tab/click so an accidental Enter can't trigger the
                   // destructive action.
                   FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                        backgroundColor: dangerColor,
                        foregroundColor: Colors.white,
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
/// confirmed, `false` if they cancelled (close-X, ghost button, or
/// barrier/Esc dismiss). Mirrors the React close-flow's
/// `closeFlow.confirmCloseActive` / `closeFlow.cancelClose` seam so the
/// later close-flow atomic can wire its callbacks with a single
/// `await showConfirmDialog(...)` call.
///
/// The dialog is `barrierDismissible: true` (outside-tap + Esc both
/// cancel), and `barrierLabel` is the [cancelLabel] (or
/// [ConfirmDialog.defaultCancelLabel]) so the modal scrim announces itself
/// as a cancel affordance to assistive tech.
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
    barrierDismissible: true,
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
