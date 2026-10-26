import 'dart:convert';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/platform/mobile_dek.dart';

class _Storage implements MobileDekStorage {
  String? value;
  bool refuseWrite = false;
  PlatformException? readFailure;

  @override
  Future<String?> readDek() async {
    if (readFailure != null) throw readFailure!;
    return value;
  }

  @override
  Future<void> writeDek(String base64Dek) async {
    if (refuseWrite) throw StateError('storage refused');
    value = base64Dek;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final legacyKey = List<int>.generate(32, (index) => 255 - index);

  test('migrates the exact legacy key before opening existing history',
      () async {
    final storage = _Storage();
    List<int>? openedWith;
    final result = await resolveHistoryDek(
      storage: storage,
      readLegacyDek: () async => base64Encode(legacyKey),
      dbExists: () => true,
      setHistoryDek: (key) async => openedWith = List.of(key),
      mint: () => fail('An existing installation never gets a new key'),
    );
    expect(result, MobileDekResolution.migrated);
    expect(base64Decode(storage.value!), legacyKey);
    expect(openedWith, legacyKey);
  });

  test('a cold readable background wrapping needs no foreground legacy access',
      () async {
    final storage = _Storage()..value = base64Encode(legacyKey);
    List<int>? openedWith;
    final result = await resolveHistoryDek(
      storage: storage,
      readLegacyDek: () =>
          fail('Cold loading must not touch biometric storage'),
      waitForForeground: () =>
          fail('A valid key must not wait for an Activity'),
      dbExists: () => true,
      setHistoryDek: (key) async => openedWith = List.of(key),
      mint: () => fail('Cold loading must not replace the key'),
    );
    expect(result, MobileDekResolution.loaded);
    expect(openedWith, legacyKey);
  });

  test('damaged background wrapping never silently falls back or mints',
      () async {
    final storage = _Storage()
      ..readFailure = PlatformException(code: 'DEK_ENVELOPE_INVALID');
    await expectLater(
      resolveHistoryDek(
        storage: storage,
        readLegacyDek: () => fail('Repair must require an explicit action'),
        dbExists: () => false,
        setHistoryDek: (_) async => fail('No history is opened on key failure'),
        mint: () => fail('A failed wrapping must never authorize minting'),
      ),
      throwsA(isA<PlatformException>()
          .having((error) => error.code, 'code', 'DEK_ENVELOPE_INVALID')),
    );
    expect(storage.value, isNull);
  });

  for (final databaseExists in [false, true]) {
    test('foreground refusal cannot mint or open history (DB=$databaseExists)',
        () async {
      final storage = _Storage();
      await expectLater(
        resolveHistoryDek(
          storage: storage,
          readLegacyDek: () async =>
              throw PlatformException(code: 'DEK_FOREGROUND_REQUIRED'),
          dbExists: () => databaseExists,
          setHistoryDek: (_) async => fail('Refusal must keep history closed'),
          mint: () => fail('Even a missing database cannot bypass legacy read'),
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(storage.value, isNull);
    });
  }

  test('refused migration write preserves the original recoverable DEK',
      () async {
    final storage = _Storage()..refuseWrite = true;
    final original = base64Encode(legacyKey);
    await expectLater(
      resolveHistoryDek(
        storage: storage,
        readLegacyDek: () async => original,
        dbExists: () => true,
        setHistoryDek: (_) async => fail('No injection before durable write'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(storage.value, isNull);
    storage.refuseWrite = false;
    List<int>? retriedWith;
    await resolveHistoryDek(
      storage: storage,
      readLegacyDek: () async => original,
      dbExists: () => true,
      setHistoryDek: (key) async => retriedWith = List.of(key),
    );
    expect(retriedWith, legacyKey);
  });

  test('interruption after durable migration resumes with the same key',
      () async {
    final storage = _Storage();
    await expectLater(
      resolveHistoryDek(
        storage: storage,
        readLegacyDek: () async => base64Encode(legacyKey),
        dbExists: () => true,
        setHistoryDek: (_) async => throw StateError('interrupted'),
      ),
      throwsA(isA<StateError>()),
    );
    List<int>? reopenedWith;
    await resolveHistoryDek(
      storage: storage,
      readLegacyDek: () =>
          fail('Committed migration must not authenticate again'),
      dbExists: () => true,
      setHistoryDek: (key) async => reopenedWith = List.of(key),
    );
    expect(reopenedWith, legacyKey);
  });

  test('missing both wrappings with existing history never regenerates a key',
      () async {
    await expectLater(
      resolveHistoryDek(
        storage: _Storage(),
        readLegacyDek: () async => null,
        dbExists: () => true,
        setHistoryDek: (_) async => fail('Existing history remains closed'),
        mint: () => fail('Existing history must keep its original key'),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('malformed stored key errors never disclose the encoded secret',
      () async {
    final storage = _Storage()..value = 'PRIVATE_KEY_MATERIAL%';
    await expectLater(
      resolveHistoryDek(
        storage: storage,
        dbExists: () => true,
        setHistoryDek: (_) async =>
            fail('Corrupt key must keep history closed'),
      ),
      throwsA(isA<StateError>().having((error) => error.message, 'message',
          'history-dek-v1: malformed stored DEK')),
    );
  });

  test('default legacy policy refuses a cold mint even without any database',
      () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    try {
      await expectLater(
        resolveHistoryDek(
          storage: _Storage(),
          dbExists: () => false,
          mint: () =>
              fail('Absence of the legacy key has not been established'),
          setHistoryDek: (_) async => fail('Cold startup must remain closed'),
        ),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'DEK_FOREGROUND_REQUIRED')),
      );
    } finally {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });

  test('startup waits for foreground only when legacy migration requires it',
      () async {
    final resumed = Completer<void>();
    final storage = _Storage();
    var foreground = false;
    List<int>? openedWith;
    final loading = resolveHistoryDek(
      storage: storage,
      dbExists: () => true,
      waitForForeground: () async {
        await resumed.future;
        foreground = true;
      },
      readLegacyDek: () async {
        if (!foreground) {
          throw PlatformException(code: 'DEK_FOREGROUND_REQUIRED');
        }
        return base64Encode(legacyKey);
      },
      setHistoryDek: (key) async => openedWith = List.of(key),
    );
    await Future<void>.delayed(Duration.zero);
    expect(openedWith, isNull);
    expect(storage.value, isNull);
    resumed.complete();
    expect(await loading, MobileDekResolution.migrated);
    expect(openedWith, legacyKey);
  });

  test('canceled legacy authentication never becomes an automatic retry',
      () async {
    final storage = _Storage();
    await expectLater(
      resolveHistoryDek(
        storage: storage,
        dbExists: () => true,
        readLegacyDek: () async =>
            throw PlatformException(code: 'AUTHENTICATION_CANCELED'),
        waitForForeground: () => fail('Cancellation must not re-prompt'),
        setHistoryDek: (_) async =>
            fail('Cancellation must keep history closed'),
      ),
      throwsA(isA<PlatformException>()
          .having((error) => error.code, 'code', 'AUTHENTICATION_CANCELED')),
    );
    expect(storage.value, isNull);
  });
}
