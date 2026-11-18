import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/system_call_mirror.dart';
import 'package:mosh/src/features/wake/wake_client.dart';
import 'package:mosh/src/platform/ios_system_calls.dart';

const _channel = MethodChannel('app.mosh/system-calls');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> asked;

  setUp(() {
    asked = [];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      asked.add(call.method);
      if (call.method == 'tokens') {
        return {'voip': 'aa', 'apns': 'bb', 'environment': 'sandbox'};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  });

  /// The runner tells Dart something, as `SystemCalls.swift` does.
  Future<void> fromRunner(String method, [Object? arguments]) =>
      messenger.handlePlatformMessage(
          _channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall(method, arguments)),
          (_) {});

  test('what the user does on the call screen reaches the app', () async {
    final calls = IosSystemCalls();
    final actions = <SystemCallAction>[];
    calls.onAction = actions.add;

    await fromRunner('answer', {'call': 'c'});
    await fromRunner('mute', {'call': 'c', 'muted': true});
    await fromRunner('end', {'call': 'c'});

    expect(asked, ['ready']);
    expect(actions[0], isA<SystemCallAnswer>());
    expect((actions[1] as SystemCallMute).muted, isTrue);
    expect(actions[2], isA<SystemCallEnd>());
  });

  test('new push tokens restart registration with what the phone holds',
      () async {
    final calls = IosSystemCalls();
    var told = 0;
    calls.onTokens = () => told++;

    await fromRunner('tokens');

    expect(told, 1);
    expect(await calls.tokens(),
        const WakeTokens(voip: 'aa', apns: 'bb', environment: 'sandbox'));
  });
}
