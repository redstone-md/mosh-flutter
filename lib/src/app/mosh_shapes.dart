import 'package:flutter/material.dart';

/// Shared geometry for chat surfaces and their controls.
abstract final class MoshShapes {
  static const messageRadius = 16.0;
  static const messageHorizontalInset = 12.0;
  static const attachmentInset = 8.0;
  static const attachmentFooterInset = messageHorizontalInset - attachmentInset;

  static const control = BorderRadius.all(Radius.circular(8));
  static const conversationRow = BorderRadius.all(Radius.circular(12));
  static const message = BorderRadius.all(Radius.circular(messageRadius));
  static const composer = BorderRadius.all(Radius.circular(16));

  /// Compact corners for sender-series joins and small embedded controls.
  static const embedded = BorderRadius.all(Radius.circular(4));

  static const attachment =
      BorderRadius.all(Radius.circular(messageRadius - attachmentInset));
  static const attachmentPadding = EdgeInsets.all(attachmentInset);

  static const controlShape = RoundedRectangleBorder(borderRadius: control);
  // The text's leading and the 2px-lower timestamp need less space above.
  static const messagePadding = EdgeInsets.fromLTRB(
      messageHorizontalInset, 8, messageHorizontalInset, 10);
  static const composerPadding = EdgeInsets.all(8);
}
