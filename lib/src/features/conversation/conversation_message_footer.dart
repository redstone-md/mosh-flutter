import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_text_metrics.dart';
import 'package:mosh/src/features/conversation/message_tone.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';

/// The time of a message and, on one the user sent, what became of it: the
/// delivery ticks, or the mark of a failure in their place. Kept outside
/// text selection.
class ConversationMessageFooter extends StatelessWidget {
  const ConversationMessageFooter({
    super.key,
    required this.message,
    required this.kind,
  });

  final ConversationMessage message;
  final ConversationKind kind;

  /// Gap between the time and the mark beside it.
  static const double _gap = MoshSpace.s1;

  // An authenticated read receipt also proves delivery, including files
  // whose offer does not use the text outbox's delivery acknowledgements.
  MessageDeliveryStatus? get _status => message.read == true
      ? MessageDeliveryStatus.delivered
      : message.deliveryStatus;

  bool get _failed => message.own && _status == MessageDeliveryStatus.failed;

  bool get _hasTicks =>
      message.own && kind == ConversationKind.dm && _status != null && !_failed;

  bool get _hasMark => _hasTicks || _failed;

  String? _clock(BuildContext context) => formatClock(message.sentAtMs,
      locale: AppLocalizations.of(context)!.localeName);

  TextStyle _timeStyle(BuildContext context) =>
      messageTimeStyle(context, MessageTone.of(context, own: message.own));

  /// Uses the same inherited font/scaler as the visible time, not a fixed
  /// character-width guess. This size reserves the inline footer's space.
  Size measure(BuildContext context) {
    final clock = _clock(context);
    final painter =
        conversationTextPainter(context, clock ?? '', _timeStyle(context))
          ..layout();
    final size = Size(
      (clock == null ? 0 : painter.width) +
          (_hasMark ? kDeliveryMarkSize + (clock == null ? 0 : _gap) : 0),
      math.max(
          clock == null ? 0 : painter.height, _hasMark ? kDeliveryMarkSize : 0),
    );
    painter.dispose();
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final tone = MessageTone.of(context, own: message.own);
    final clock = _clock(context);
    final full = formatClockFull(message.sentAtMs,
        locale: AppLocalizations.of(context)!.localeName);
    return SelectionContainer.disabled(
      child: SizedBox.fromSize(
        size: measure(context),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (clock != null && full != null)
            Tooltip(
                message: full, child: Text(clock, style: _timeStyle(context))),
          if (_hasMark && clock != null) const SizedBox(width: _gap),
          if (_hasTicks)
            DeliveryTicks(
                status: _status, read: message.read == true, tone: tone),
          // The bubble keeps its colour and marks the failure where the
          // ticks would be; the row under the bubble says it in words.
          if (_failed)
            ExcludeSemantics(
                child: Icon(MoshIcons.errorFill,
                    size: kDeliveryMarkSize, color: tone.error)),
        ]),
      ),
    );
  }
}
