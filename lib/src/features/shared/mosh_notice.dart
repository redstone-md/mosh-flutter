import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_spinner.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors, MoshLevel;

/// How much a notice asks of its reader. The quiet tones lie on the panel
/// level and differ only in the colour of their mark; a warning and an error
/// take the whole plate.
enum MoshNoticeTone {
  secure,
  open,
  neutral,
  success,
  warning,
  error;

  bool get quiet => this != warning && this != error;

  /// A quiet notice is a card of the panel level; a toned one is a plate
  /// of its container colour, without an edge.
  Decoration _surface(MoshColors c, BorderRadius corners) => switch (this) {
        warning =>
          BoxDecoration(color: c.warningContainer, borderRadius: corners),
        error => BoxDecoration(color: c.errorContainer, borderRadius: corners),
        _ => MoshLevel.card(c, corners),
      };

  Color _mark(MoshColors c) => switch (this) {
        secure => c.primary,
        open => c.tertiary,
        neutral => c.onSurfaceVariant,
        success => c.success,
        warning => c.onWarningContainer,
        error => c.onErrorContainer,
      };

  /// The ink of the title, and of the detail and the controls on a toned
  /// plate.
  Color _ink(MoshColors c) => quiet ? c.onSurface : _mark(c);
}

/// The Banner and the Inline note of the Banner card: a mark, a [title] and
/// a [detail] on a toned surface. A banner says something about the whole
/// conversation or the whole app and may end with one control on its first
/// line: the close button of [onClose], or the action of [onAction]. An
/// [inline] note is the same message inside a form, a step tighter in its
/// corners.
///
/// The text is one semantic node and the control another.
class MoshNotice extends StatelessWidget {
  const MoshNotice({
    super.key,
    required this.tone,
    required this.icon,
    this.title,
    this.detail,
    this.onClose,
    this.actionLabel,
    this.onAction,
    this.busy = false,
    this.inline = false,
    this.radius,
    this.maxLines,
    bool? announced,
  })  : announced = announced ?? tone == MoshNoticeTone.error,
        assert(title != null || detail != null),
        assert(onClose == null || actionLabel == null,
            'a notice ends with one control');

  final MoshNoticeTone tone;
  final IconData icon;
  final String? title;
  final String? detail;

  /// Shows the close button. While [busy] it takes no press.
  final VoidCallback? onClose;

  /// The one thing to do about the notice, with [onAction]. While [busy] it
  /// spins and takes no press.
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool busy;
  final bool inline;

  /// Corners other than the banner's or the inline note's: the notice of a
  /// call matches the dock under it.
  final double? radius;

  /// Whether a screen reader is told when the notice appears. An error
  /// always is; a note that takes a form's place asks for it.
  final bool announced;

  /// The most lines the [detail] takes before it is cut with an ellipsis;
  /// a screen reader still hears all of it.
  final int? maxLines;

  /// A line of the notice's text, which the mark and the control stand on.
  static const _line = MoshSpace.s5;
  static const _pad = MoshSpace.s4;

  /// How many lines of text a notice [height] tall has room for, at the
  /// reader's text size: what [maxLines] takes where the room is short.
  static int linesIn(BuildContext context, double height) =>
      ((height - _pad * 2) / MediaQuery.textScalerOf(context).scale(_line))
          .clamp(0, 100)
          .floor();

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final tail = _tail(context, colors);
    return Semantics(
      container: true,
      liveRegion: announced,
      child: DecoratedBox(
        decoration: tone._surface(
            colors,
            BorderRadius.all(Radius.circular(
                radius ?? (inline ? MoshRadius.medium : MoshRadius.large)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
                start: _pad, top: _pad, end: MoshSpace.s3),
            child: Icon(icon, size: _line, color: tone._mark(colors)),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                  top: _pad, bottom: _pad, end: tail == null ? _pad : 0),
              child: _text(context, colors),
            ),
          ),
          if (tail != null) tail,
        ]),
      ),
    );
  }

  Widget _text(BuildContext context, MoshColors colors) {
    final text = Theme.of(context).textTheme;
    final ink = tone._ink(colors);
    return Semantics(
      label: [title, detail].nonNulls.join('. '),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: MoshSpace.s1,
        children: [
          if (title != null)
            Text(title!, style: text.titleSmall?.copyWith(color: ink)),
          // Alone, the detail is the message and takes the title's line.
          if (detail != null)
            Text(detail!,
                maxLines: maxLines,
                overflow: maxLines == null ? null : TextOverflow.ellipsis,
                style: title == null
                    ? text.bodyMedium?.copyWith(color: ink)
                    : text.bodySmall?.copyWith(
                        color: tone.quiet ? colors.onSurfaceVariant : ink)),
        ],
      ),
    );
  }

  /// The control the notice ends with. It is taller than the first line and
  /// centred on it, and keeps its own room to the notice's edge.
  Widget? _tail(BuildContext context, MoshColors colors) {
    final touch = MoshControl.touch(Theme.of(context).platform);
    // On a toned plate a control takes the plate's ink.
    final ink = tone.quiet ? null : tone._ink(colors);
    final Widget control;
    final double edge;
    if (onClose case final close?) {
      control = IconButton(
        tooltip: AppLocalizations.of(context)!.dialogClose,
        onPressed: busy ? null : close,
        color: ink,
        icon: const Icon(MoshIcons.close),
      );
      edge = touch ? MoshSpace.s1 : MoshSpace.s2;
    } else if (actionLabel case final label?) {
      control = MoshLoading(
        loading: busy,
        child: OutlinedButton.icon(
          onPressed: onAction,
          style: ink == null
              ? null
              : OutlinedButton.styleFrom(
                  foregroundColor: ink, side: BorderSide(color: ink)),
          icon: busy ? const MoshSpinner() : null,
          label: Text(label),
        ),
      );
      edge = MoshSpace.s3;
    } else {
      return null;
    }
    final above =
        _pad + _line / 2 - MoshControl.height(Theme.of(context).platform) / 2;
    return Padding(
      padding: EdgeInsetsDirectional.only(
          start: MoshSpace.s3, top: above, bottom: above, end: edge),
      child: control,
    );
  }
}
