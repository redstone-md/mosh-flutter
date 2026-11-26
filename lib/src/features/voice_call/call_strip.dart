import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'call_button.dart';
import 'call_who_line.dart';

/// The Call strip of the Minimized call card: a call that is not open, on
/// the phone, which has no title bar. It lies above the screen and has the
/// plate's parts: a press on the name does [onOpen] (with [openTooltip]),
/// the buttons do their own work.
class CallStrip extends StatelessWidget {
  const CallStrip(
      {super.key,
      required this.label,
      required this.peer,
      required this.line,
      required this.controls,
      required this.onOpen,
      this.openTooltip});

  final String label, peer;
  final CallLine line;
  final List<CallControl> controls;
  final VoidCallback? onOpen;
  final String? openTooltip;

  @override
  Widget build(BuildContext context) {
    final who = InkWell(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            minHeight: MoshControl.height(Theme.of(context).platform)),
        child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: CallWhoLine(peer: peer, line: line, wide: true)),
      ),
    );
    return Material(
      color: MoshColors.of(context).surfaceContainerLowest,
      child: Semantics(
        label: label,
        container: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              MoshSpace.s4, MoshSpace.s1, MoshSpace.s2, MoshSpace.s1),
          child: Row(spacing: MoshSpace.s2, children: [
            Expanded(
                child: openTooltip == null
                    ? who
                    : Tooltip(message: openTooltip, child: who)),
            for (final control in controls) CallMiniButton(control: control),
          ]),
        ),
      ),
    );
  }
}
