// Verifies `persistenceWarningProvider`
// over the five
// branches: browser-demo, available+encrypted, available+!encrypted, !available,
// and bridge-throws. Overrides `bridgeFacadeProvider` with a scripted
// bridge (ADR 0025).
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../support/scriptable_bridge.dart';
import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/rust/moss_runtime.dart';
import 'package:mosh/src/rust/persistence.dart';
import 'package:mosh/src/rust/secure_storage.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/persistence_warning_provider.dart';

/// A bridge whose `nativeRuntimeStatus` returns [status].
ScriptableBridge _bridgeReporting(NativeRuntimeStatus status) =>
    ScriptableBridge()..seedNativeRuntimeStatus(status);

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
  test('browser-demo link-mode -> null', () async {
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(_bridgeReporting(
        _status(
            linkMode: 'browser-demo', available: true, encryptedAtRest: true),
      )),
    ]);
    addTearDown(container.dispose);
    expect(await _read(container), isNull);
  });

  test('available && encryptedAtRest -> null', () async {
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(_bridgeReporting(
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
      bridgeFacadeProvider.overrideWithValue(_bridgeReporting(
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
      bridgeFacadeProvider.overrideWithValue(_bridgeReporting(
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

  test('nativeRuntimeStatus throws -> error kind, reason set', () async {
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(ScriptableBridge()
        ..failAlways(BridgeMethod.nativeRuntimeStatus,
            error: StateError('bridge exploded'))),
    ]);
    addTearDown(container.dispose);
    final result = await _read(container);
    expect(result, isA<PersistenceWarning>());
    expect(result!.kind, PersistenceWarningKind.error);
    expect(result.reason, isNotEmpty);
    expect(result.reason, contains('bridge exploded'));
  });
}
