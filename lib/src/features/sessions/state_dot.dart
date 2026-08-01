/// Colored dot indicating a channel/group/session state. Shared by the
/// sessions list (`_SessionRow`) and the rail-item widgets
/// (`ChannelRailItem` / `GroupRailItem`) so the React `rail-dot-*` element
/// is rendered by exactly one widget (DRY -- previously a private copy in
/// `sessions_screen.dart`).
///
/// Colors mirror the React `rail-dot rail-dot-${state}` palette: idle = grey,
/// waiting/connecting = amber, ready = teal/green, default = grey.
library;

import 'package:flutter/material.dart';

/// A 10x10 circular dot colored by `state`.
class StateDot extends StatelessWidget {
  const StateDot({super.key, required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _dotColor(state),
      ),
    );
  }
}

/// State dot color: idle = grey, waiting/connecting = amber, ready = teal,
/// default = grey. Mirrors the React `rail-dot-*` palette.
Color _dotColor(String state) {
  switch (state) {
    case 'idle':
      return Colors.grey;
    case 'waiting':
    case 'connecting':
      return Colors.amber;
    case 'ready':
      return Colors.teal;
    default:
      return Colors.grey;
  }
}
