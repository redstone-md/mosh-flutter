import 'package:flutter/material.dart';

/// Shared geometry for chat surfaces and their controls.
abstract final class MoshShapes {
  static const control = BorderRadius.all(Radius.circular(8));
  static const conversationRow = BorderRadius.all(Radius.circular(12));
  static const message = BorderRadius.all(Radius.circular(16));
  static const composer = BorderRadius.all(Radius.circular(16));

  /// A message's 16px corner minus its 12px horizontal content inset.
  static const embedded = BorderRadius.all(Radius.circular(4));

  static const controlShape = RoundedRectangleBorder(borderRadius: control);
  // The text's leading and the 2px-lower timestamp need less space above.
  static const messagePadding = EdgeInsets.fromLTRB(12, 8, 12, 10);
  static const composerPadding = EdgeInsets.all(8);
}
