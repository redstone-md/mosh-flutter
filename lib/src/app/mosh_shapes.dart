import 'package:flutter/material.dart';

import 'mosh_dimensions.dart';

/// Shared geometry for chat surfaces and their controls, on the
/// [MoshRadius] scale of Foundations.
abstract final class MoshShapes {
  static const messageRadius = MoshRadius.large;
  static const messageHorizontalInset = 12.0;
  static const attachmentInset = 8.0;
  static const attachmentFooterInset = messageHorizontalInset - attachmentInset;

  static const control = BorderRadius.all(Radius.circular(MoshRadius.small));
  static const conversationRow =
      BorderRadius.all(Radius.circular(MoshRadius.medium));
  static const menu = BorderRadius.all(Radius.circular(MoshRadius.medium));
  static const message = BorderRadius.all(Radius.circular(messageRadius));
  static const composer = BorderRadius.all(Radius.circular(MoshRadius.large));

  /// Compact corners for sender-series joins and small embedded controls.
  static const embedded =
      BorderRadius.all(Radius.circular(MoshRadius.extraSmall));

  static const attachment =
      BorderRadius.all(Radius.circular(messageRadius - attachmentInset));
  static const attachmentPadding = EdgeInsets.all(attachmentInset);

  static const controlShape = RoundedRectangleBorder(borderRadius: control);
  // The text's leading and the 2px-lower timestamp need less space above.
  static const messagePadding = EdgeInsets.fromLTRB(
      messageHorizontalInset, 8, messageHorizontalInset, 10);
  static const composerPadding = EdgeInsets.all(8);
}
