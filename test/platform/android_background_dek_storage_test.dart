import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/platform/mobile_dek.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.mosh.mosh/access');
  const storage = AndroidBackgroundDekStorage(channel: channel);
  final key = Uint8List.fromList(List<int>.generate(32, (index) => index + 1));

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('native background bytes reopen history without interactive methods',
      () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'readBackgroundDek') return key;
      fail('Cold background loading must not request authentication or writes');
    });
    List<int>? openedWith;
    await resolveHistoryDek(
      storage: storage,
      readLegacyDek: () =>
          fail('The original biometric reader must remain idle'),
      dbExists: () => true,
      setHistoryDek: (bytes) async => openedWith = List.of(bytes),
    );
    expect(openedWith, key);
  });

  test('native acknowledgement without retained bytes cannot create history',
      () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'readBackgroundDek') return null;
      if (call.method == 'installBackgroundDek') {
        expect(call.arguments, key);
        return null;
      }
      fail('Unexpected interactive key method');
    });
    await expectLater(
      resolveHistoryDek(
        storage: storage,
        readLegacyDek: () async => null,
        dbExists: () => false,
        mint: () => key,
        setHistoryDek: (_) async =>
            fail('Unverified bytes must never open a DB'),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('malformed native DEK is refused before any history is opened',
      () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => Uint8List(31),
    );
    await expectLater(
      storage.readDek(),
      throwsA(isA<PlatformException>()
          .having((error) => error.code, 'code', 'DEK_INVALID_LENGTH')),
    );
  });

  test('explicit repair sends only the validated original bytes', () async {
    Uint8List? repairedWith;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method != 'recoverBackgroundDek') fail('Unexpected method');
      repairedWith = call.arguments as Uint8List;
      return null;
    });
    await storage.recoverDek(base64Encode(key));
    expect(repairedWith, key);
  });
}
