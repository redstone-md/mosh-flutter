import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/modal_focus_trap.dart';
import 'package:mosh/src/features/shared/optical_icon.dart';

/// Confirmation with explicit consent, safe initial focus and Esc/back cancellation.
class ConfirmDialog extends StatelessWidget {
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

  static const String defaultCancelLabel = 'Cancel';

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onCancel();
        },
        child: ModalFocusTrap(
          onEscape: onCancel,
          autofocus: true,
          child: _ConfirmDialogCard(this),
        ),
      );
}

class _ConfirmDialogCard extends StatelessWidget {
  const _ConfirmDialogCard(this.dialog);

  final ConfirmDialog dialog;

  @override
  Widget build(BuildContext context) {
    final cancel = dialog.cancelLabel ?? ConfirmDialog.defaultCancelLabel;
    return Semantics(
      label: dialog.title,
      container: true,
      // `showDialog` already creates a `ModalRoute` the assistive layer
      // treats as a modal route boundary. We do NOT set
      // `scopesRoute: true` here: that requires `explicitChildNodes: true`
      // (framework assertion) AND duplicates the modal-route scoping the
      // `showDialog` host already provides. Keeping `container: true,
      // label: dialog.title` gives the labeled-group announcement.
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: MoshColors.lineStrong),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
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
                // in the top-right corner -- and the dialog.title's leading
                // margin stays clear of it.
                Align(
                  alignment: Alignment.topRight,
                  child:
                      _CloseButton(tooltip: cancel, onPressed: dialog.onCancel),
                ),
                // The alert icon (decorative) in a 38x38 tinted rounded
                // square.
                _AlertIcon(dangerColor: dialog.dangerColor),
                const SizedBox(height: 16),
                // Title: 16px/1.25 bold, fg-1.
                Text(
                  dialog.title,
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
                  dialog.body,
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
                    TextButton(onPressed: dialog.onCancel, child: Text(cancel)),
                    // Danger confirm button: danger background. No
                    // `autofocus` -- the close-X gets
                    // initial focus (see file header); confirm requires an
                    // explicit Tab/click so an accidental Enter can't trigger the
                    // destructive action.
                    FilledButton(
                      onPressed: dialog.onConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: dialog.dangerColor,
                        // The on-fill ink follows the fill's luminance. The
                        // crossover is where dark-ink and light-ink
                        // contrasts are equal (WCAG midpoint, ~0.183), NOT
                        // 0.5: the default danger (L≈0.28) is a light fill
                        // and takes the dark ink; a dark custom fill takes
                        // the light one (CodeAnt PR #12).
                        foregroundColor:
                            dialog.dangerColor.computeLuminance() > 0.183
                                ? MoshColors.mossInk
                                : MoshColors.fg1,
                      ),
                      child: Text(dialog.confirmLabel),
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
      visualDensity: VisualDensity.standard,
      // >=40px hit area for comfortable desktop targeting.
      splashRadius: 20,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
        child: OpticalIcon(
          icon: Icons.warning,
          offset: const Offset(0, -1),
          size: 18,
          color: dangerColor,
        ),
      ),
    );
  }
}

/// Returns whether the user confirmed; backdrop taps never confirm or dismiss.
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
