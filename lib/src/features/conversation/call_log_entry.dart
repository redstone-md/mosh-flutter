import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show kLiveNumberFontFeatures;
import 'package:mosh/src/features/conversation/conversation_call_binding.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/message_tone.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// The event kind literal for a missed call.
const String callEventKindMissed = 'missed';

/// The event kind for a call between devices whose call engines cannot talk.
const String callEventKindUpdateRequired = 'update_required';

/// How long a call lasted, in words: "2 min 5 s", or "45 s" under a minute.
/// Empty for a call that never connected.
String formatCallDuration(AppLocalizations l, BigInt durationMs) {
  final total =
      durationMs <= BigInt.zero ? 0 : (durationMs ~/ BigInt.from(1000)).toInt();
  if (total == 0) return '';
  final minutes = total ~/ 60, seconds = total % 60;
  return minutes == 0
      ? l.callLogSeconds(seconds)
      : l.callLogMinutesSeconds(minutes, seconds);
}

/// The Call log entry card: a call in the feed of a DM, a bubble of its own
/// on the side and in the colour of whoever made it. The arrow tells who
/// rang and, in the error colour, that the call never connected; the
/// handset rings back.
class CallLogEntry extends StatelessWidget {
  const CallLogEntry({
    super.key,
    required this.event,
    required this.outgoing,
    required this.sentAtMs,
    required this.conversationId,
    required this.l,
  });

  final CallEvent event;

  /// Whether the user made the call.
  final bool outgoing;

  /// When it rang.
  final BigInt? sentAtMs;

  /// The DM the call was in, which the handset rings back; null where the
  /// entry is drawn outside one.
  final String? conversationId;

  final AppLocalizations l;

  bool get _notConnected =>
      event.kind == callEventKindMissed ||
      event.kind == callEventKindUpdateRequired;

  String get _title => switch (event.kind) {
        callEventKindMissed =>
          outgoing ? l.callLogNoAnswerLabel : l.callLogMissedLabel,
        callEventKindUpdateRequired => l.callLogUpdateRequiredLabel,
        _ => outgoing ? l.callLogOutgoingLabel : l.callLogIncomingLabel,
      };

  /// When it rang and, for a call that connected, how long it lasted.
  String get _detail => [
        formatClock(sentAtMs, locale: l.localeName),
        formatCallDuration(l, event.durationMs),
      ].where((part) => part != null && part.isNotEmpty).join(', ');

  /// The arrow and the line beside it: who rang, when and for how long.
  Widget _meta(ThemeData theme, MessageTone tone) {
    final full = formatClockFull(sentAtMs, locale: l.localeName);
    final detail = Text(_detail,
        style: theme.textTheme.labelMedium!.copyWith(
            color: tone.quiet, fontFeatures: kLiveNumberFontFeatures));
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: MoshSpace.s1,
      children: [
        Icon(outgoing ? MoshIcons.callMade : MoshIcons.callReceived,
            size: MoshSpace.s4,
            color: _notConnected ? tone.error : tone.accent),
        Flexible(
            child:
                full == null ? detail : Tooltip(message: full, child: detail)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = MessageTone.of(context, own: outgoing);
    // The button is taller than the glyph it shows; the entry's own padding
    // gives way to it, so the handset stays 12 px from the edge.
    final slack = (MoshControl.height(theme.platform) - MoshSpace.s6) / 2;
    return Container(
      padding: EdgeInsetsDirectional.only(
          start: MoshSpace.s4, end: MoshSpace.s3 - slack),
      decoration:
          BoxDecoration(color: tone.fill, borderRadius: MoshShapes.message),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: MoshSpace.s6 - slack,
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: MoshSpace.s2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_title,
                      style: theme.textTheme.labelLarge!
                          .copyWith(color: tone.ink)),
                  _meta(theme, tone),
                ],
              ),
            ),
          ),
          _CallBackButton(
              conversationId: conversationId,
              color: tone.accent,
              label: l.callStart),
        ],
      ),
    );
  }
}

/// The handset of a call entry: it starts a call the way the conversation's
/// header does. It rests while that call is being set up, so a second press
/// cannot ask again, and where no call module is bound.
class _CallBackButton extends ConsumerStatefulWidget {
  const _CallBackButton(
      {required this.conversationId, required this.color, required this.label});

  final String? conversationId;
  final Color color;
  final String label;

  @override
  ConsumerState<_CallBackButton> createState() => _CallBackButtonState();
}

class _CallBackButtonState extends ConsumerState<_CallBackButton> {
  bool _starting = false;

  Future<void> _call(String conversationId) async {
    setState(() => _starting = true);
    try {
      await startConversationCall(ref, context, conversationId);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.conversationId;
    final bound = ref.watch(conversationCallBindingProvider) != null;
    return IconButton(
      icon: const Icon(MoshIcons.call),
      iconSize: MoshSpace.s6,
      color: widget.color,
      tooltip: widget.label,
      onPressed: id == null || !bound || _starting ? null : () => _call(id),
    );
  }
}
