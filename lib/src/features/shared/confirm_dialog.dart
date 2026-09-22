// Shared ConfirmDialog: a centered modal confirmation dialog used by
// destructive-action flows. Rendered via Flutter's `showDialog`, which
// provides the modal barrier + focus trap natively. Cancel only happens
// via the Cancel button, the close-X, or Esc -- a stray scrim tap is a
// NO-OP: `showDialog` is `barrierDismissible: false`. Esc is wired
// through a `KeyboardListener` (the same pattern the call modals +
// `PeerStatusDrawer` use), and Android system-back cancels via
// `PopScope(canPop: false, onPopInvokedWithResult:)` (back=cancel).
//
// This atomic is JUST the widget + the `showConfirmDialog` helper -- NOT
// the close-flow wiring (that is a later atomic that passes `title` /
// `body` / `confirmLabel` from its own ARB keys and calls `onCancel` /
// `onConfirm`).
//
// The card is a `Dialog`-shaped card: close-X in the top-right corner,
// alert icon in a tinted rounded square, h2-title + muted body, and an
// actions row of ghost TextButton (cancel) + danger FilledButton
// (confirm). The danger color defaults to `MoshColors.danger`
// (`Color(0xFFE86A5A)`), overridable via the `dangerColor` prop.
// The card is wrapped in `Semantics(container: true, label: title)`; the
// close-X carries a tooltip + semantics label of the cancel label, and
// the decorative alert icon is excluded from semantics. The dialog
// autofocuses the first focusable child (the close-X) -- the SAFE
// default for a destructive dialog (an accidental Enter dismisses, it
// does not confirm).
library;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:flutter/services.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';

/// A centered modal confirmation dialog. Construct directly and pass to
/// `showDialog`, or use the [showConfirmDialog] helper which returns `true`
/// if the user confirmed, `false` (or null) if they cancelled.
///
/// - `title`        -> the dialog title
/// - `body`         -> the dialog body
/// - `confirmLabel` -> the danger button text
/// - `cancelLabel`  -> the ghost button text + the close-X label
///   (defaults to [defaultCancelLabel] when null so callers without a
///   localized "Cancel" still get a sane label)
/// - `onCancel`     -> invoked on close-X, ghost button, or Esc /
///   Android system-back (the host wires scrim-no-op through
///   [showConfirmDialog])
/// - `onConfirm`    -> invoked on the danger button
///
/// The widget is a [StatefulWidget] only because it owns the `FocusNode`
/// the `KeyboardListener` (Esc -> `onCancel`) attaches to.
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

  /// The dialog title.
  final String title;

  /// The dialog body.
  final String body;

  /// The danger (confirm) button label.
  final String confirmLabel;

  /// The ghost (cancel) button label AND the close-X label. Falls back to
  /// [defaultCancelLabel] when null so the dialog always has a cancel
  /// affordance; callers pass a localized label from their ARB key.
  final String? cancelLabel;

  /// Invoked when the user cancels (close-X, ghost button, or
  /// barrier/Esc dismiss via [showConfirmDialog]).
  final VoidCallback onCancel;

  /// Invoked when the user confirms (danger button).
  final VoidCallback onConfirm;

  /// Danger accent color (`Color(0xFFE86A5A)` by default). Drives the
  /// alert-icon tint + the confirm button background. Overridable for
  /// tests + theming.
  final Color dangerColor;

  /// Default cancel label used when [cancelLabel] is null; the close-flow
  /// atomic will pass a localized label instead.
  static const String defaultCancelLabel = 'Cancel';

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  // A single [FocusNode] owned here and attached to a [KeyboardListener]
  // wrapping the card. `autofocus: true` pulls focus into the dialog on
  // mount, and the key handler forwards Esc to `onCancel`. The call modals
  // (`IncomingCallModal` / `OutgoingCallModal`) + `PeerStatusDrawer` use
  // the same `KeyboardListener`-Esc pattern; this dialog matches them.
  late final FocusNode _focusNode = FocusNode(debugLabel: 'ConfirmDialog');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The `KeyboardListener` is the outermost node so Esc is caught before
    // any child focusables; `autofocus: true` pulls focus into the dialog
    // on open. The `PopScope` gates Android
    // system-back: `canPop: false` blocks the default pop (the scrim is
    // already a no-op via `barrierDismissible: false`), and
    // `onPopInvokedWithResult` fires `onCancel` when a back press is
    // attempted -- Esc/back parity so the user is never trapped in a
    // destructive confirm with no escape (on Android the expectation for
    // a modal is back=cancel).
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
          // `KeyDownEvent` only -- not `KeyRepeatEvent`/`KeyUpEvent` --
          // so a held Esc does not fire `onCancel` repeatedly (matches
          // the call modals).
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
      // treats as a modal route boundary. We do NOT set
      // `scopesRoute: true` here: that requires `explicitChildNodes: true`
      // (framework assertion) AND duplicates the modal-route scoping the
      // `showDialog` host already provides. Keeping `container: true,
      // label: title` gives the labeled-group announcement.
      child: Dialog(
        // Material `Dialog` clamps by
        // `Dialog` constraints; cap at 380 so wide screens do not stretch
        // the card. `insetPadding` gives the backdrop a 24px padding.
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        // The 1px line border -- the call cards carry no border, so this
        // sits on the dialog rather than in the shared dialogTheme.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: MoshColors.lineStrong),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            // 22px padding; 16px gap between rows.
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The close-X sits in the top-right corner. Render it as
                // a real header Row right-aligned at the top of the card
                // so it is robustly hit-testable (a `Stack + Positioned`
                // with a negative offset places the IconButton outside
                // the dialog's clip/hit-test bounds and is flaky under
                // tests + mouse). The visual result matches -- a small X
                // in the top-right corner -- and the title's leading
                // margin stays clear of it.
                Align(
                  alignment: Alignment.topRight,
                  child: _CloseButton(tooltip: cancel, onPressed: onCancel),
                ),
                // The alert icon (decorative) in a 38x38 tinted rounded
                // square.
                _AlertIcon(dangerColor: dangerColor),
                const SizedBox(height: 16),
                // Title: 16px/1.25 bold, fg-1.
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
                // Body: fg-2, 12.5px/1.55.
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
                // Actions: ghost Cancel + danger Confirm, right-aligned.
                // `Wrap` with `alignment: end` + `spacing: 8` reproduces
                // the right-aligned single-line layout when the buttons
                // fit. The Ahem test font makes the close-flow's longer
                // labels ("Cancel" + "Leave channel") overflow a fixed
                // `Row`, so `Wrap` degrades to a wrapped stack instead --
                // matching the narrow-surface fallback.
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    // Ghost cancel button: no background, primary-foreground
                    // text.
                    TextButton(onPressed: onCancel, child: Text(cancel)),
                    // Danger confirm button: danger background. No
                    // `autofocus` -- the close-X gets
                    // initial focus (see file header); confirm requires an
                    // explicit Tab/click so an accidental Enter can't trigger the
                    // destructive action.
                    FilledButton(
                      onPressed: onConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: dangerColor,
                        // The on-fill ink follows the fill's luminance. The
                        // crossover is where dark-ink and light-ink
                        // contrasts are equal (WCAG midpoint, ~0.183), NOT
                        // 0.5: the default danger (L≈0.28) is a light fill
                        // and takes the dark ink; a dark custom fill takes
                        // the light one (CodeAnt PR #12).
                        foregroundColor: dangerColor.computeLuminance() > 0.183
                            ? MoshColors.mossInk
                            : MoshColors.fg1,
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

/// The close-X button. A 28x28 transparent square button with a
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
      // Compact splash to match the tight 28px hit area.
      splashRadius: 16,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
    );
  }
}

/// The alert icon (IconAlertTriangle size=18) in a 38x38 rounded tinted
/// square. `excludeSemantics` keeps the icon out of the semantics tree
/// (it is decorative; the title/body carry the meaning).
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
          // A 12% tint of the danger color.
          color: dangerColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          // Material's `Icons.warning` is the standard filled
          // alert-triangle glyph.
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
/// Android system-back). A single `await showConfirmDialog(...)` call
/// wires the close-flow callbacks.
///
/// The dialog is `barrierDismissible: false` -- a scrim tap is a NO-OP,
/// so a stray tap on Android cannot silently cancel a destructive
/// confirm. The dim `barrierColor` still shows (the scrim is visible,
/// just not dismissible). Esc (via the `KeyboardListener`) and Android
/// system-back (via the `PopScope`) both cancel, matching the Android
/// back=cancel modal expectation. `barrierLabel` is
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
    // The backdrop is NOT dismissible: a scrim tap is a no-op (the dim
    // scrim still shows via `barrierColor`).
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
