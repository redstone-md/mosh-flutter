import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/linked_dm_test.dart';

/// Exercises the same scenario/control path locally, without Android claims.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const recorder = MethodChannel('com.llfbandit.record/messages');
  setUp(() {
    // The host tester supports the idle microphone handle used by the composer.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recorder, (call) async {
      if (call.method == 'create' || call.method == 'dispose') return null;
      throw StateError('The text DM scenario must not record audio');
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(recorder, null));
  linkedDmTest(android: false);
}
