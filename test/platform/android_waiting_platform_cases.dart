import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';

Map<String, Object?> state(int revision, {bool enabled = true}) => {
      'revision': revision,
      'intentRevision': revision,
      'interactive': false,
      'waitingEnabled': enabled,
      'serviceRunning': enabled,
      'setupComplete': true,
      'notificationsAllowed': true,
      'batteryExempt': false,
      'restriction': null,
    };

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.mosh.mosh/waiting');

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('a late native callback cannot turn saved Stop waiting back on',
      () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      return state(call.method == 'stop' ? 3 : 1,
          enabled: call.method != 'stop');
    });
    final platform = AndroidWaitingPlatform();
    addTearDown(platform.dispose);
    await platform.refresh();
    await platform.stop();
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('waitingStateChanged', state(2))),
      (_) {},
    );
    expect(platform.state!.waitingEnabled, false);
    expect(platform.state!.revision, 3);
  });

  test('a denied service start never claims enabled service availability',
      () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'enable') {
        throw PlatformException(code: 'WAITING_START_DENIED');
      }
      return state(1, enabled: false);
    });
    final platform = AndroidWaitingPlatform();
    addTearDown(platform.dispose);
    await platform.refresh();
    await expectLater(platform.enable(), throwsA(isA<PlatformException>()));
    expect(platform.state!.waitingEnabled, false);
    expect(platform.state!.serviceRunning, false);
  });
  test('cold key refusal releases execution without changing saved intent',
      () async {
    MethodCall? failure;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'startupFailed') failure = call;
      return {
        ...state(call.method == 'startupFailed' ? 8 : 7),
        'serviceRunning': call.method != 'startupFailed',
        'restriction': call.method == 'startupFailed' ? 'keyUnavailable' : null
      };
    });
    final platform = AndroidWaitingPlatform();
    addTearDown(platform.dispose);
    await platform.refresh();
    await platform.startupFailed('keyUnavailable');
    expect(
        failure!.arguments, {'reason': 'keyUnavailable', 'intentRevision': 7});
    expect(platform.state!.waitingEnabled, true);
    expect(platform.state!.serviceRunning, false);
    expect(platform.state!.restriction, 'keyUnavailable');
  });
}
