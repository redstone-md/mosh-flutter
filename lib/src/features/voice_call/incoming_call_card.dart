import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/mosh_dialog.dart'
    show moshDangerButtonStyle;
import 'call_button.dart';

/// The Incoming call card of the Minimized call card: a call rings in the
/// upper corner of the desktop's window, so it can be answered without
/// leaving the chat. A press on the person opens the call.
class IncomingCallCard extends StatelessWidget {
  const IncomingCallCard(
      {super.key,
      required this.label,
      required this.peer,
      required this.status,
      required this.decline,
      required this.accept,
      required this.onOpen});

  static const double width = 320;

  final String label, peer, status;

  final CallControl decline;

  /// Null once the call has been answered.
  final CallControl? accept;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final l = AppLocalizations.of(context)!;
    return Semantics(
      label: label,
      container: true,
      child: SizedBox(
        width: width,
        child: Material(
          color: MoshLevel.popup.fill(colors),
          elevation: MoshLevel.popup.elevation!.dp,
          shape: MoshLevel.popup.shape(colors),
          child: Padding(
            padding: const EdgeInsets.all(MoshSpace.s4),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: MoshSpace.s4,
                children: [
                  _who(context, colors),
                  Row(spacing: MoshSpace.s2, children: [
                    Expanded(
                        child: _answer(decline, l.callDecline,
                            style: moshDangerButtonStyle(context))),
                    if (accept case final accept?)
                      Expanded(child: _answer(accept, l.callAccept)),
                  ]),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _who(BuildContext context, MoshColors colors) {
    final text = Theme.of(context).textTheme;
    return Tooltip(
      message: AppLocalizations.of(context)!.callExpand,
      child: InkWell(
        onTap: onOpen,
        borderRadius: MoshLevel.popup.corners,
        child: Row(spacing: MoshSpace.s3, children: [
          ExcludeSemantics(child: Avatar(name: peer, radius: 24)),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(peer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          text.titleMedium?.copyWith(color: colors.onSurface)),
                  Text(status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ]),
          ),
        ]),
      ),
    );
  }

  /// A Button with the control's glyph and a word for what it does.
  Widget _answer(CallControl control, String label, {ButtonStyle? style}) =>
      FilledButton.icon(
          onPressed: control.onPressed,
          style: style,
          icon: Icon(control.icon),
          label: Text(label));
}
