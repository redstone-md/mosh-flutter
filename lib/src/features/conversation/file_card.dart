import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show kLiveNumberFontFeatures;
import 'package:mosh/src/features/conversation/attachment_actions.dart';
import 'package:mosh/src/features/conversation/conversation_attachment.dart';
import 'package:mosh/src/features/conversation/conversation_text_metrics.dart';
import 'package:mosh/src/features/conversation/message_tone.dart';
import 'package:mosh/src/features/shared/mosh_progress_bar.dart';

/// The File card: a file's name, its size and, on its plate, the one thing
/// that can be done with it now. The whole card is the target of that
/// action. It has no background of its own: it sits in a bubble, in either
/// of its colours, or in the list of shared files, and takes the width it
/// is given.
class FileCard extends StatelessWidget {
  const FileCard({
    super.key,
    required this.attachment,
    required this.tone,
    required this.action,
    this.footer,
  });

  final ConversationAttachment attachment;
  final MessageTone tone;

  /// What a press does and how the plate shows it; null for a file with
  /// nothing to do, which shows the glyph of its kind.
  final AttachmentAction? action;

  /// The time of a message that is this file alone: it ends the card's
  /// last line.
  final Widget? footer;

  /// Side of the plate, and so the height of the card.
  static const double plate = MoshSpace.s10;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final failed = attachment.failed;
    final progress = attachment.progress;
    final act = action;
    final glyph = SizedBox.square(
      dimension: plate,
      child: Icon(act?.glyph ?? attachmentGlyph(attachment),
          size: MoshSpace.s5, color: failed ? tone.failGlyph : tone.glyph),
    );
    final card = Row(
      spacing: MoshSpace.s3,
      // The plate keeps its place whatever the last line holds.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: failed ? tone.failPlate : tone.plate,
          borderRadius: MoshShapes.attachment,
          clipBehavior: Clip.antiAlias,
          // The plate is the control a keyboard and a screen reader find,
          // named for the action. The text beside it stays part of the
          // message, so a long press there still opens the message's menu.
          child: act == null
              ? glyph
              : Tooltip(
                  message: act.tooltip,
                  child: Semantics(
                    container: true,
                    label: act.label,
                    button: true,
                    enabled: act.onPressed != null,
                    onTap: act.onPressed,
                    excludeSemantics: true,
                    child: InkWell(
                      overlayColor: MoshState.layer(tone.glyph),
                      excludeFromSemantics: true,
                      onTap: act.onPressed,
                      child: glyph,
                    ),
                  ),
                ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            // With the bar between them the two lines sit close, to stay
            // within the plate's height.
            spacing: progress == null ? MoshSpace.s1 : 0,
            children: [
              MiddleCutText(attachment.descriptor.fileName,
                  style: text.labelLarge!.copyWith(color: tone.ink)),
              // The bar runs above the detail, so the detail stays the last
              // line, level with the time.
              if (progress != null)
                MoshProgressBar(
                    fraction: progress.fraction,
                    semanticsLabel:
                        l.attachmentStateDownloading(progress.percent),
                    color: tone.accent,
                    track: tone.track),
              Row(spacing: MoshSpace.s2, children: [
                Expanded(
                  child: Text(
                    attachmentDetail(attachment, l),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium!.copyWith(
                        color: failed ? tone.error : tone.quiet,
                        fontFeatures: kLiveNumberFontFeatures),
                  ),
                ),
                if (footer case final footer?) footer,
              ]),
            ],
          ),
        ),
      ],
    );
    if (act == null) return card;
    // The whole card is the pointer's target.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: MoshShapes.attachment,
        overlayColor: MoshState.layer(tone.ink),
        canRequestFocus: false,
        excludeFromSemantics: true,
        onTap: act.onPressed,
        child: card,
      ),
    );
  }
}

/// One line of [text]. A name too long for it is cut in the middle, so its
/// start and its end, the extension included, both show.
class MiddleCutText extends StatelessWidget {
  const MiddleCutText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  /// Characters kept at the end of a name that is cut.
  static const int _kept = 9;

  bool _fits(BuildContext context, String candidate, double width) {
    final painter = conversationTextPainter(context, candidate, style)
      ..layout();
    final fits = painter.width <= width;
    painter.dispose();
    return fits;
  }

  /// [text] as it shows in [width]: whole, or its longest start that fits
  /// beside an ellipsis and its end.
  String _cut(BuildContext context, double width) {
    if (text.length <= _kept || _fits(context, text, width)) return text;
    final end = text.substring(text.length - _kept);
    var fits = 1, over = text.length - _kept;
    while (over - fits > 1) {
      final mid = (fits + over) ~/ 2;
      if (_fits(context, '${text.substring(0, mid)}…$end', width)) {
        fits = mid;
      } else {
        over = mid;
      }
    }
    return '${text.substring(0, fits)}…$end';
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Text(
          _cut(context, constraints.maxWidth),
          semanticsLabel: text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      );
}
