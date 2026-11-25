import 'package:flutter/material.dart';

import 'mosh_dimensions.dart';

/// Shared geometry for chat surfaces and their controls, on the
/// [MoshRadius] scale of Foundations.
abstract final class MoshShapes {
  /// A bubble's own padding, the same on every side, so the 12 px corners
  /// of an attachment stay concentric with its 20 px ones.
  static const bubblePadding = EdgeInsets.all(MoshSpace.s2);

  /// Text in a bubble, and the caption of a picture, is set in a little
  /// further than the bubble's padding.
  static const bubbleInset =
      EdgeInsetsDirectional.only(start: MoshSpace.s2, end: MoshSpace.s1);

  static const control = BorderRadius.all(Radius.circular(MoshRadius.small));

  /// The well of a text field or a select.
  static const field = BorderRadius.all(Radius.circular(MoshRadius.medium));

  /// Buttons, chips, badges and everything else drawn as a pill.
  static const pill = StadiumBorder();

  /// The corners of a pill, where a border radius is asked for.
  static const pillCorners = BorderRadius.all(Radius.circular(MoshRadius.full));

  /// A row of the chat list, in every state.
  static const conversationRow =
      BorderRadius.all(Radius.circular(MoshRadius.large));
  static const menu = BorderRadius.all(Radius.circular(MoshRadius.medium));

  /// The corners of a bubble, and the tighter one its sender's side takes
  /// between the neighbours of a run.
  static const message =
      BorderRadius.all(Radius.circular(MoshRadius.largeIncreased));
  static const messageJoin = Radius.circular(MoshRadius.small);
  static const composer =
      BorderRadius.all(Radius.circular(MoshRadius.extraLarge));

  /// Compact corners for small embedded marks: a fingerprint, a keycap.
  static const embedded =
      BorderRadius.all(Radius.circular(MoshRadius.extraSmall));

  /// The plate of a file and the preview of a picture.
  static const attachment =
      BorderRadius.all(Radius.circular(MoshRadius.medium));

  static const controlShape = RoundedRectangleBorder(borderRadius: control);
  static const composerPadding = EdgeInsets.all(MoshSpace.s1);

  /// The gap between the controls of the composer.
  static const double composerGap = MoshSpace.s1;
}
