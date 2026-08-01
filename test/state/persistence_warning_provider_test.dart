// Verifies `persistenceWarningProvider` (1-в-1 with React's
// `useRuntimePersistenceStatus` in
// src/features/private-dm/use-runtime-persistence-status.ts) over the five
// branches: browser-demo, available+encrypted, available+!encrypted, !available,
// and gateway-throws. Overrides `gatewayProvider` with a controllable fake.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/rust/moss_runtime.dart';
import 'package:mosh/src/rust/persistence.dart';
import 'package:mosh/src/rust/secure_storage.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/persistence_warning_provider.dart';

/// Subclass of FakeGateway whose `nativeRuntimeStatus()` returns a canned
/// status (or throws), so the provider's five branches are exercisable.
class _ControllableFakeGateway extends FakeGateway {
  _ControllableFakeGateway(this._status, {this.throwOnStatus = false});
  final NativeRuntimeStatus? _status;
  final bool throwOnStatus;

  @override
  Future<NativeRuntimeStatus> nativeRuntimeStatus() {
    if (throwOnStatus) {
      throw StateError('gateway exploded');
    }
    return Future.value(_status);
  }
}

NativeRuntimeStatus _status({
  required String linkMode,
  required bool available,
  required bool encryptedAtRest,
  String? persistenceError,
}) =>
    NativeRuntimeStatus(
      moss: MossRuntimeStatus(
        linkMode: linkMode,
        libraryName: 'moss.dll',
        requiredSymbols: const [],
        available: true,
        checkedPaths: const [],
      ),
      secureStorage: const SecureStorageStatus(
        backend: 'os-keychain',
        service: 'app.mosh.desktop',
        available: true,
      ),
      persistence: PersistenceRuntimeStatus(
        backend: 'redb+aes-256-gcm+os-keychain',
        database: 'unavailable',
        available: available,
        encryptedAtRest: encryptedAtRest,
        error: persistenceError,
      ),
      openmlsSmoke: const OpenMlsSmokeRuntimeStatus(),
      openmlsRoundtrip: const OpenMlsRoundTripRuntimeStatus(),
    );

Future<PersistenceWarning?> _read(ProviderContainer c) =>
    c.read(persistenceWarningProvider.future);

void main() {
  test(
      'browser-demo link-mode -> null (React: status.moss.link_mode === "browser-demo")',
      () async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(_ControllableFakeGateway(
        _status(
            linkMode: 'browser-demo', available: true, encryptedAtRest: true),
      )),
    ]);
    addTearDown(container.dispose);
    expect(await _read(container), isNull);
  });

  test(
      'available && encryptedAtRest -> null (React: persistence available && encrypted_at_rest)',
      () async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(_ControllableFakeGateway(
        _status(linkMode: 'dynamic', available: true, encryptedAtRest: true),
      )),
    ]);
    addTearDown(container.dispose);
    expect(await _read(container), isNull);
  });

  test(
      'available && !encryptedAtRest -> unavailable kind, reason == persistence error',
      () async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(_ControllableFakeGateway(
        _status(
          linkMode: 'dynamic',
          available: true,
          encryptedAtRest: false,
          persistenceError: 'encryption off',
        ),
      )),
    ]);
    addTearDown(container.dispose);
    final result = await _read(container);
    expect(result, isA<PersistenceWarning>());
    expect(result!.kind, PersistenceWarningKind.unavailable);
    expect(result.reason, 'encryption off');
  });

  test('!available -> unavailable kind (persistence not running)', () async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(_ControllableFakeGateway(
        _status(
          linkMode: 'dynamic',
          available: false,
          encryptedAtRest: false,
          persistenceError: 'no instance',
        ),
      )),
    ]);
    addTearDown(container.dispose);
    final result = await _read(container);
    expect(result, isA<PersistenceWarning>());
    expect(result!.kind, PersistenceWarningKind.unavailable);
    expect(result.reason, 'no instance');
  });

  test(
      'nativeRuntimeStatus throws -> error kind, reason set (React: catch branch)',
      () async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(
        _ControllableFakeGateway(null, throwOnStatus: true),
      ),
    ]);
    addTearDown(container.dispose);
    final result = await _read(container);
    expect(result, isA<PersistenceWarning>());
    expect(result!.kind, PersistenceWarningKind.error);
    expect(result.reason, isNotEmpty);
    expect(result.reason, contains('gateway exploded'));
  });
}
