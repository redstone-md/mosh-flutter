import 'package:flutter/widgets.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// The colours of a bubble and of what sits in it. A message the user sent
/// is on [MoshColors.outgoing] with the dark inks made for that fill;
/// everything else, the list of shared files included, is on a surface.
/// The two rows of TONES in the Components cards.
@immutable
class MessageTone {
  const MessageTone._({
    required this.fill,
    required this.ink,
    required this.quiet,
    required this.plate,
    required this.glyph,
    required this.error,
    required this.failPlate,
    required this.failGlyph,
    required this.accent,
    required this.onAccent,
    required this.rest,
  });

  /// The tone of a message in the palette around [context]: [own] for one
  /// the user sent.
  factory MessageTone.of(BuildContext context, {required bool own}) =>
      MessageTone.from(MoshColors.of(context), own: own);

  factory MessageTone.from(MoshColors c, {required bool own}) => own
      ? MessageTone._(
          fill: c.outgoing,
          ink: c.onOutgoing,
          quiet: c.onOutgoingVariant,
          plate: c.onOutgoingVariant,
          glyph: c.outgoing,
          error: c.outgoingError,
          failPlate: c.outgoingError,
          failGlyph: c.outgoing,
          accent: c.onOutgoing,
          onAccent: c.outgoing,
          rest: c.onOutgoingVariant,
        )
      : MessageTone._(
          fill: c.incoming,
          ink: c.onSurface,
          quiet: c.onSurfaceMuted,
          plate: c.surfaceContainerHighest,
          glyph: c.onSurfaceVariant,
          error: c.error,
          failPlate: c.errorContainer,
          failGlyph: c.error,
          accent: c.primary,
          onAccent: c.onPrimary,
          rest: c.outline,
        );

  /// The bubble itself.
  final Color fill;

  /// Text, and the quieter text beside it: the time, a size, a state.
  final Color ink, quiet;

  /// The plate of a file and the glyph on it; [failPlate] and [failGlyph]
  /// when its transfer failed.
  final Color plate, glyph, failPlate, failGlyph;

  /// A failure told in words or by a mark.
  final Color error;

  /// The one control of an attachment and the content on it, such as the
  /// play button of a voice message; [accent] also fills what has played.
  final Color accent, onAccent;

  /// What has not happened yet: the bars still to play, the track of a
  /// transfer.
  final Color rest;
}
