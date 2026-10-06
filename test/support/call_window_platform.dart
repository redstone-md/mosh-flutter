import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Window-manager method-channel recording for the shared child UI.
class CallWindowPlatform {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
}
