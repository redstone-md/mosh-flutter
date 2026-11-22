import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/platform/android_wake.dart';

const _channel = MethodChannel('app.mosh.mosh/wake');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// The runner as MoshWake.kt answers, in an FCM build when [wakeable].
  void runner({bool wakeable = false, String? installation}) {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      return switch (call.method) {
        'wakeable' => wakeable,
        'tokens' => installation == null ? null : {'fcm': installation},
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  }

  test('the FCM build registers its Firebase installation id', () async {
    runner(wakeable: true, installation: 'fid-1');
    final wake = AndroidWake();

    expect(await wake.wakeable(), isTrue);
    expect((await wake.tokens())?.toJson(), {'fcm': 'fid-1'});
  });

  test('a build without a push service is not woken', () async {
    runner();

    expect(await AndroidWake().wakeable(), isFalse);
  });

  test('a new installation id restarts registration', () async {
    runner(wakeable: true, installation: 'fid-2');
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
