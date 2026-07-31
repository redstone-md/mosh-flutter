// M-3 unit test for the Dart half of the mobile DEK platform channel. Drives
// `resolveHistoryDek` directly with a hand-fake storage + controllable
// db-exists predicate + recording setHistoryDek, so the three branches
// (present-key load, missing-key+no-DB mint, missing-key+DB-exists
// fail-closed) are covered with no device and no Rust runtime. This mirrors
// the brief's "hand fake" option (mocktail is not a dev_dependency in this
// project, and a hand fake keeps the test dependency-free).
//
// The test does NOT exercise `initMobileDek()` itself: that wiring imports
// the real frb `api.setHistoryDek` (which needs RustLib.init) and `dart:io`
// Platform (host is not Android), so it is the device-only half. The
// decision logic -- which is where the read/mint/fail-closed correctness
// lives -- is fully covered here.

import 'dart:convert' show base64, base64Decode, base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/platform/mobile_dek.dart';

/// Hand-fake Keystore. Records writes so the mint branch can assert the
/// base64 DEK was durably stored before the inject call.
class _FakeDekStorage implements MobileDekStorage {
  _FakeDekStorage({String? initial}) : _store = initial;

  String? _store;
  final List<String> writes = [];
  int readCount = 0;

  @override
  Future<String?> readDek() async {
    readCount++;
    return _store;
  }

  @override
  Future<void> writeDek(String base64Dek) async {
    writes.add(base64Dek);
    _store = base64Dek;
  }
}

/// Recording inject callback. Captures the last DEK handed to Rust so a test
/// can assert the exact bytes (and that the call happened at all).
Future<void> Function(List<int> dek) _recordingInject(
  List<List<int>> recorded,
) {
  return (List<int> dek) async {
    recorded.add(List<int>.from(dek));
  };
}

/// Deterministic 32-byte mint for reproducible assertions.
List<int> _fixedMint() => List<int>.generate(32, (i) => (i * 7) % 256);

void main() {
  test('present DEK is base64-decoded and injected (loaded branch)', () async {
    final Uint8List expected = Uint8List.fromList(_fixedMint());
    final _FakeDekStorage storage =
        _FakeDekStorage(initial: base64Encode(expected));
    final List<List<int>> injected = [];

    final result = await resolveHistoryDek(
      storage: storage,
      dbExists: () => fail('dbExists must not be called when a DEK is present'),
      setHistoryDek: _recordingInject(injected),
      // mint must NOT run on the load branch.
      mint: () => fail('mint must not run when a DEK is present'),
    );

    expect(result, MobileDekResolution.loaded);
    expect(storage.readCount, 1);
    expect(storage.writes, isEmpty,
        reason: 'load branch must not write the Keystore');
    expect(injected, [expected],
        reason: 'setHistoryDek must be called once with the decoded bytes');
  });

  test('missing DEK + no DB: mints 32 bytes, writes base64, then injects',
      () async {
    final _FakeDekStorage storage = _FakeDekStorage(initial: null);
    final List<List<int>> injected = [];

    final result = await resolveHistoryDek(
      storage: storage,
      dbExists: () => false,
      setHistoryDek: _recordingInject(injected),
      mint: _fixedMint,
    );

    expect(result, MobileDekResolution.minted);
    expect(storage.readCount, 1);
    // The minted DEK must be written to the Keystore BEFORE the inject call
    // (so a crash between write and inject never leaves Rust with a DEK the
    // Keystore lacks).
    expect(storage.writes, [_fixedMintEncoded()],
        reason: 'minted DEK must be base64-encoded and written to Keystore');
    expect(injected, [_fixedMint()],
        reason: 'setHistoryDek must be called once with the minted bytes');
    // Round-trip: what was written must decode back to the injected DEK.
    expect(base64Decode(storage.writes.single),
        Uint8List.fromList(injected.single));
  });

  test('missing DEK + DB exists: fails closed (throws, never mints/injects)',
      () async {
    final _FakeDekStorage storage = _FakeDekStorage(initial: null);
    final List<List<int>> injected = [];

    await expectLater(
      resolveHistoryDek(
        storage: storage,
        dbExists: () => true,
        setHistoryDek: _recordingInject(injected),
        mint: () => fail('mint must not run on the fail-closed branch'),
      ),
      throwsA(isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        contains('DEK absent from Keystore but history DB exists'),
      )),
    );

    expect(storage.readCount, 1);
    expect(storage.writes, isEmpty,
        reason: 'fail-closed branch must not write the Keystore');
    expect(injected, isEmpty,
        reason: 'fail-closed branch must not call setHistoryDek');
  });

  test('stored DEK of wrong length fails fast (corrupt Keystore entry)',
      () async {
    final _FakeDekStorage storage =
        _FakeDekStorage(initial: base64.encode(List<int>.filled(31, 9)));
    final List<List<int>> injected = [];

    await expectLater(
      resolveHistoryDek(
        storage: storage,
        dbExists: () => fail('dbExists must not be called on a corrupt DEK'),
        setHistoryDek: _recordingInject(injected),
        mint: () => fail('mint must not run on a corrupt DEK'),
      ),
      throwsA(isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        contains('stored DEK has wrong length 31'),
      )),
    );

    expect(injected, isEmpty,
        reason: 'a corrupt stored DEK must not be injected');
  });
}

/// base64 of `_fixedMint()`, computed once for the mint-branch write assertion.
String _fixedMintEncoded() => base64Encode(_fixedMint());
