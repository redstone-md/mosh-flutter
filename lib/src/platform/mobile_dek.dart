import 'dart:convert' show base64Decode, base64Encode;
import 'dart:io' show Directory, File, Platform;
import 'dart:math' show Random;
import 'dart:typed_data' show Uint8List;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'package:flutter/foundation.dart'
    show debugPrint, listEquals, visibleForTesting;
import 'package:mosh/src/rust/api/private_dm.dart' as api show setHistoryDek;
import 'package:mosh/src/platform/app_data_dir.dart' show appDataDir;

/// The Keystore key the DEK is stored under. Mirrors the Rust constant
/// `persistence::DEK_KEY` (`"history-dek-v1"`) so both sides address the same
/// secret. Rust's `Persistence::open` uses this key on the desktop keychain;
/// the mobile inject path uses it in the Android Keystore namespace below.
const String _dekKey = 'history-dek-v1';

/// The Android Keystore storage namespace. Mirrors the desktop
/// `OsSecureSecretStore` SERVICE_NAME `app.mosh.desktop` so the mobile and
/// desktop backends occupy symmetric namespaces (`app.mosh.mobile` /
/// `app.mosh.desktop`) under the same `app.mosh.*` scheme.
const String _storageNamespace = 'app.mosh.mobile';

/// Original foreground-only wrapping for migration and explicit repair.
/// Never reset or algorithm-migrate the retained recovery material.
@visibleForTesting
AndroidOptions buildDekAndroidOptions() => const AndroidOptions.biometric(
      storageNamespace: _storageNamespace,
      resetOnError: false,
      migrateOnAlgorithmChange: false,
      enforceBiometrics: true,
      biometricType: AndroidBiometricType.biometricOrDeviceCredential,
      biometricPromptTitle: 'Unlock Mosh',
      biometricPromptSubtitle: 'Authenticate to access your conversations',
      biometricPromptNegativeButton: 'Cancel',
    );

/// The DEK length in bytes (AES-256-GCM key). Must match the Rust
/// `set_history_dek` validation (`dek.len() == 32`).
const int _dekLength = 32;

/// Outcome of a DEK resolution, for assertability in tests.
enum MobileDekResolution {
  /// An existing background DEK was read and injected without UI authentication.
  loaded,

  /// No DEK was stored and no DB existed, so a fresh DEK was minted, written
  /// to the Keystore, and injected.
  minted,

  /// The original foreground-authenticated DEK was durably migrated.
  migrated,
}

/// Base64 storage boundary; writes promise durable commit before returning.
abstract class MobileDekStorage {
  /// Read the stored base64 DEK, or `null` if absent.
  Future<String?> readDek();

  /// Write the base64 DEK. Must not return until the write is durable.
  Future<void> writeDek(String base64Dek);
}

/// Installation-owned durable wrapping, usable after first Android unlock.
class AndroidBackgroundDekStorage implements MobileDekStorage {
  const AndroidBackgroundDekStorage({
    MethodChannel channel = const MethodChannel('app.mosh.mosh/access'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<String?> readDek() async {
    final bytes = await _channel.invokeMethod<Uint8List>('readBackgroundDek');
    if (bytes == null) return null;
    if (bytes.length != _dekLength) {
      throw PlatformException(code: 'DEK_INVALID_LENGTH');
    }
    return base64Encode(bytes);
  }

  @override
  Future<void> writeDek(String base64Dek) => _channel.invokeMethod<void>(
        'installBackgroundDek',
        _decodeDek(base64Dek),
      );

  Future<void> recoverDek(String base64Dek) => _channel.invokeMethod<void>(
        'recoverBackgroundDek',
        _decodeDek(base64Dek),
      );
}

Future<String?> _readLegacyDek() {
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
    throw PlatformException(code: 'DEK_FOREGROUND_REQUIRED');
  }
  final storage = FlutterSecureStorage(aOptions: buildDekAndroidOptions());
  return storage.read(key: _dekKey, aOptions: storage.aOptions);
}

/// Prefer the background wrapping; otherwise migrate the authenticated legacy
/// key. Mint only after absence is established and no encrypted DB exists.
/// Both native durable readback and this adapter's exact-byte readback precede
/// [setHistoryDek]. The production [readLegacyDek] refuses background access.
Future<MobileDekResolution> resolveHistoryDek({
  required MobileDekStorage storage,
  Future<String?> Function()? readLegacyDek,
  required bool Function() dbExists,
  required Future<void> Function(List<int> dek) setHistoryDek,
  List<int> Function() mint = _secureMint32,
}) async {
  final stored = await storage.readDek();
  if (stored != null) {
    await setHistoryDek(_decodeDek(stored));
    return MobileDekResolution.loaded;
  }
  // The production legacy reader refuses non-foreground calls, including on a
  // fresh installation. Missing background material never authorizes a mint.
  final legacy = await readLegacyDek?.call();
  if (legacy == null && dbExists()) {
    throw StateError(
      'history-dek-v1: DEK absent from Keystore but history DB exists; '
      'refusing to mint a fresh DEK that would orphan persisted history',
    );
  }

  final dek = legacy == null ? Uint8List.fromList(mint()) : _decodeDek(legacy);
  if (dek.length != _dekLength) {
    throw StateError(
      'minted DEK has wrong length ${dek.length} (expected $_dekLength)',
    );
  }
  await _installAndCheck(storage, dek);
  await setHistoryDek(dek);
  return legacy == null
      ? MobileDekResolution.minted
      : MobileDekResolution.migrated;
}

Uint8List _decodeDek(String encoded) {
  final Uint8List bytes;
  try {
    bytes = base64Decode(encoded);
  } on FormatException {
    throw StateError('history-dek-v1: malformed stored DEK');
  }
  if (bytes.length != _dekLength) {
    throw StateError(
      'history-dek-v1: stored DEK has wrong length ${bytes.length}',
    );
  }
  return bytes;
}

Future<void> _installAndCheck(MobileDekStorage storage, Uint8List dek) async {
  await storage.writeDek(base64Encode(dek));
  final readback = await storage.readDek();
  if (readback == null || !listEquals(_decodeDek(readback), dek)) {
    throw StateError('history-dek-v1: committed DEK readback mismatch');
  }
}

/// Mints `_dekLength` cryptographically random bytes. Wrapped so tests can
/// inject a deterministic mint.
List<int> _secureMint32() {
  final Random rng = Random.secure();
  return List<int>.generate(_dekLength, (_) => rng.nextInt(256));
}

/// The path `construct_runtime` opens. M-5 (ADR 0010): uses the bridged
/// app_data_dir from `app_data_dir.appDataDir()` (which Dart resolves via
/// `getApplicationSupportDirectory()` at startup and hands to Rust via
/// `setAppDataDir`) so Dart's DB-exists check and Rust's open agree on the
/// exact file. Falls back to `temp/mosh/history.redb` (the pre-M-5 path) with
/// a warning if the bridge has not run yet -- should not happen given
/// `main()` calls `setAppDataDirBridge()` before `initMobileDek()`, but the
/// guard keeps a misordered caller correct rather than crashing.
File _historyRedbPath() {
  final String? injected = appDataDir();
  final Directory moshDir;
  if (injected != null && injected.isNotEmpty) {
    // Bridged app_data_dir: `<app_data_dir>/mosh/history.redb`, the SAME path
    // Rust opens via `resolve_data_dir(Some(<app_data_dir>))`. `mosh` is the
    // subdir both sides append so the DB + attachments stay co-located.
    moshDir = Directory('$injected${Platform.pathSeparator}mosh');
  } else {
    // Bridge not yet run -- fall back to the pre-M-5 temp path. This is a
    // divergence from Rust (which would also keep temp in this case, so the
    // two still agree), but log it loudly so the misorder is visible.
    debugPrint(
      'mosh: app_data_dir not yet bridged; falling back to temp/mosh for '
      '_historyRedbPath. setAppDataDirBridge() should run before '
      'initMobileDek() in main().',
    );
    moshDir =
        Directory('${Directory.systemTemp.path}${Platform.pathSeparator}mosh');
  }
  moshDir.createSync(recursive: true);
  return File('${moshDir.path}${Platform.pathSeparator}history.redb');
}

/// Load the same installation DEK before opening Rust history. A valid native
/// wrapping needs no Activity; missing wrapping requires foreground migration.
/// Desktop and iOS retain their existing keychain path.
Future<MobileDekResolution?> initMobileDek() async {
  if (!Platform.isAndroid) {
    // Desktop (Windows/macOS/Linux) and iOS keep using Rust's
    // OsSecureSecretStore via Persistence::open; no DEK injection.
    return null;
  }
  return resolveHistoryDek(
    storage: const AndroidBackgroundDekStorage(),
    readLegacyDek: _readLegacyDek,
    dbExists: () => _historyRedbPath().existsSync(),
    setHistoryDek: (List<int> dek) => api.setHistoryDek(dek: dek),
  );
}

/// Explicit foreground repair; ordinary cold reads never enter this path.
Future<void> recoverMobileDek() async {
  if (!Platform.isAndroid) return;
  final encoded = await _readLegacyDek();
  if (encoded == null) {
    throw StateError('history-dek-v1: legacy recovery material is unavailable');
  }
  final dek = _decodeDek(encoded);
  const storage = AndroidBackgroundDekStorage();
  await storage.recoverDek(encoded);
  final committed = await storage.readDek();
  if (committed == null || !listEquals(_decodeDek(committed), dek)) {
    throw StateError('history-dek-v1: recovered DEK readback mismatch');
  }
  await api.setHistoryDek(dek: dek);
}
