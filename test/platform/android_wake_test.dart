import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/wake/wake_client.dart';
import 'package:mosh/src/platform/android_wake.dart';

const _channel = MethodChannel('app.mosh.mosh/wake');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// The runner as MoshWake.kt answers in a build woken through `platform`.
  void runner({String? platform, String? installation}) {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      return switch (call.method) {
        'platform' => platform,
        'tokens' => installation == null ? null : {'fcm': installation},
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  }

  test('the FCM build registers its Firebase installation id', () async {
    runner(platform: 'fcm', installation: 'fid-1');
    final wake = AndroidWake();

    expect(await wake.wakeable(), isTrue);
    expect(await wake.tokens(), const FcmWakeTokens('fid-1'));
  });

  test('a build without a push service is not woken', () async {
    runner();

    expect(await AndroidWake().wakeable(), isFalse);
  });

  test('a new installation id restarts registration', () async {
    runner(platform: 'fcm', installation: 'fid-2');
    final wake = AndroidWake();
    var told = 0;
    wake.onTokens = () => told++;

    await messenger.handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('tokens')),
        (_) {});

    expect(told, 1);
  });
}
