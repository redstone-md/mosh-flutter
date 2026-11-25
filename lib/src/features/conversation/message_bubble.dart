import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/message_tone.dart';

/// The bubble of the Message card: it hugs what it holds, in the colour of
/// its [tone]. In a run from one sender the corners on the sender's side
/// tighten between neighbours. A deleted message keeps its place in the run
/// but gives up its colour for an outline.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.id,
    required this.tone,
    required this.own,
    required this.grouped,
    required this.continuesBelow,
    required this.child,
    this.gone = false,
  });

  /// Names the bubble for tests and tools: `message-bubble-<id>`.
  final String id;
  final MessageTone tone;

  /// Which side the sender is on: the trailing one for the user.
  final bool own;

  /// Whether the run continues above and below this bubble.
  final bool grouped, continuesBelow;

  /// A deleted message, or one awaiting its deletion.
  final bool gone;

  final Widget child;

  BorderRadiusDirectional get _corners {
    final round = MoshShapes.message.topLeft;
    final top = grouped ? MoshShapes.messageJoin : round;
    final bottom = continuesBelow ? MoshShapes.messageJoin : round;
    return BorderRadiusDirectional.only(
      topStart: own ? round : top,
      bottomStart: own ? round : bottom,
      topEnd: own ? top : round,
      bottomEnd: own ? bottom : round,
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        key: ValueKey('message-bubble-$id'),
        padding: MoshShapes.bubblePadding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: gone ? null : tone.fill,
          border: gone
              ? Border.all(color: MoshColors.of(context).outlineVariant)
              : null,
          borderRadius: _corners,
        ),
        child: child,
      );
}
