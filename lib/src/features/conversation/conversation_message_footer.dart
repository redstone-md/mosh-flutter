import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_text_metrics.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';

/// Timestamp and actual delivery state, kept outside text selection.
class ConversationMessageFooter extends StatelessWidget {
  const ConversationMessageFooter({
    super.key,
    required this.message,
    required this.kind,
  });

  final ConversationMessage message;
  final ConversationKind kind;

  // An authenticated read receipt also proves delivery, including files
  // whose offer does not use the text outbox's delivery acknowledgements.
  MessageDeliveryStatus? get _status => message.read == true
      ? MessageDeliveryStatus.delivered
      : message.deliveryStatus;

  bool get _hasTicks =>
      message.own &&
      kind == ConversationKind.dm &&
      _status != null &&
      _status != MessageDeliveryStatus.failed;

  String? _clock(BuildContext context) => formatClock(message.sentAtMs,
      locale: AppLocalizations.of(context)!.localeName);

  TextStyle get _timeStyle => kMessageTimeStyle.copyWith(
      color: message.own ? MoshColors.fg2 : MoshColors.fg3);

  /// Uses the same inherited font/scaler as the visible time, not a fixed
  /// character-width guess. This size reserves the inline footer's space.
  Size measure(BuildContext context) {
    final clock = _clock(context);
    final painter = conversationTextPainter(context, clock ?? '', _timeStyle)
      ..layout();
    final size = Size(
      (clock == null ? 0 : painter.width) +
          (_hasTicks ? kCompactDeliverySize + (clock == null ? 0 : 5) : 0),
      math.max(clock == null ? 0 : painter.height,
          _hasTicks ? kCompactDeliverySize : 0),
    );
    painter.dispose();
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final clock = _clock(context);
    final full = formatClockFull(message.sentAtMs,
        locale: AppLocalizations.of(context)!.localeName);
    return Transform.translate(
        offset: const Offset(0, 2),
        child: SelectionContainer.disabled(
          child: SizedBox.fromSize(
            size: measure(context),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (clock != null && full != null)
                Tooltip(message: full, child: Text(clock, style: _timeStyle)),
              if (_hasTicks) ...[
                if (clock != null) const SizedBox(width: 5),
                DeliveryTicks(
                    status: _status,
                    read: message.read == true,
                    color: _timeStyle.color,
                    compact: true),
              ],
            ]),
          ),
        ));
  }
}
