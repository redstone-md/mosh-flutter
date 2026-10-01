import 'package:flutter/material.dart';

/// Shared geometry for chat surfaces and their controls.
abstract final class MoshShapes {
  static const control = BorderRadius.all(Radius.circular(8));
  static const message = BorderRadius.all(Radius.circular(12));
  static const composer = BorderRadius.all(Radius.circular(16));

  /// A message's 12px corner minus its 8px content inset.
  static const embedded = BorderRadius.all(Radius.circular(4));

  static const controlShape = RoundedRectangleBorder(borderRadius: control);
  static const messagePadding = EdgeInsets.all(8);
  static const composerPadding = EdgeInsets.all(8);
}
