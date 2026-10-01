import 'package:flutter/material.dart';

/// Shared geometry for chat surfaces and their controls.
abstract final class MoshShapes {
  static const messageRadius = 16.0;
  static const attachmentInset = 8.0;

  static const control = BorderRadius.all(Radius.circular(8));
  static const conversationRow = BorderRadius.all(Radius.circular(12));
  static const message = BorderRadius.all(Radius.circular(messageRadius));
  static const composer = BorderRadius.all(Radius.circular(16));

  /// Compact corners for sender-series joins and small embedded controls.
  static const embedded = BorderRadius.all(Radius.circular(4));

  static const attachment =
      BorderRadius.all(Radius.circular(messageRadius - attachmentInset));
  static const attachmentPadding = EdgeInsets.all(attachmentInset);

  /// Insets each actual bubble corner, including its tighter series joins.
  static BorderRadius attachmentCorners(BorderRadius outer) {
    Radius inset(Radius radius) =>
        (radius - const Radius.circular(attachmentInset))
            .clamp(minimum: Radius.zero);
    return BorderRadius.only(
      topLeft: inset(outer.topLeft),
      topRight: inset(outer.topRight),
      bottomLeft: inset(outer.bottomLeft),
      bottomRight: inset(outer.bottomRight),
    );
  }

  static const controlShape = RoundedRectangleBorder(borderRadius: control);
  // The text's leading and the 2px-lower timestamp need less space above.
  static const messagePadding = EdgeInsets.fromLTRB(12, 8, 12, 10);
  static const composerPadding = EdgeInsets.all(8);
}
