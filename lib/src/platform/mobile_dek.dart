import 'dart:convert' show base64Decode, base64Encode;
import 'dart:io' show Directory, File, Platform;
import 'dart:math' show Random;
import 'dart:typed_data' show Uint8List;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
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

/// Builds the Android Keystore options for the at-rest history DEK.
///
/// M-7 (ADR 0011): user-presence gating is DEFAULT-ON. We use the
/// `AndroidOptions.biometric(...)` constructor which selects the
/// KeyStore-backed `AES_GCM_NoPadding` key+storage ciphers (the only
/// combination that supports `setUserAuthenticationRequired`) and
/// requires the device to have a biometric OR device credential
/// (PIN/pattern/password) enrolled, failing closed on an insecure
/// device rather than storing the DEK unauthenticated. The namespace
/// `app.mosh.mobile` is preserved from M-3.
@visibleForTesting
AndroidOptions buildDekAndroidOptions() => const AndroidOptions.biometric(
      storageNamespace: _storageNamespace,
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
  /// An existing DEK was read from the Keystore and injected.
  loaded,

  /// No DEK was stored and no DB existed, so a fresh DEK was minted, written
  /// to the Keystore, and injected.
  minted,
}

/// Minimal read/write seam over the Keystore so the decision logic can be
/// tested with a hand fake. Mirrors the slice of `FlutterSecureStorage` the
/// inject path actually uses: `read` + `write` with the Android options.
abstract class MobileDekStorage {
  /// Read the stored base64 DEK, or `null` if absent.
  Future<String?> readDek();

  /// Write the base64 DEK. Must not return until the write is durable.
  Future<void> writeDek(String base64Dek);
}

/// Real `FlutterSecureStorage`-backed implementation of [MobileDekStorage].
/// Constructed with the Android namespace options; only meaningful on
/// Android (the inject path is gated `Platform.isAndroid` upstream).
class _FlutterSecureStorageDek implements MobileDekStorage {
  _FlutterSecureStorageDek()
      : _storage = FlutterSecureStorage(
          aOptions: buildDekAndroidOptions(),
        );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readDek() =>
      _storage.read(key: _dekKey, aOptions: _storage.aOptions);

  @override
  Future<void> writeDek(String base64Dek) => _storage.write(
        key: _dekKey,
        value: base64Dek,
        aOptions: _storage.aOptions,
      );
}

/// Resolve and inject the at-rest history DEK for the mobile platform
/// channel. See the module doc for the three branches.
///
/// [storage] is the Keystore seam (real or fake). [dbExists] returns true if
/// the encrypted history DB already exists at the path `construct_runtime`
/// will open (mirrors Rust's `temp/mosh/history.redb` fallback today). The
/// [setHistoryDek] callback is the frb inject call (real or stubbed). The
/// [mint] callback mints `_dekLength` random bytes (defaults to
/// `Random.secure()` so production never uses a weak RNG; tests override it
/// for determinism).
///
/// Throws a [StateError] when the Keystore has no DEK but the DB already
/// exists: this is the fail-closed branch, mirroring Rust's
/// `Persistence::open` refusal to mint a fresh DEK when a DB exists (it
/// would orphan all persisted history). The error message names the branch
/// so a device log makes the cause obvious.
Future<MobileDekResolution> resolveHistoryDek({
  required MobileDekStorage storage,
  required bool Function() dbExists,
  required Future<void> Function(List<int> dek) setHistoryDek,
  List<int> Function() mint = _secureMint32,
}) async {
  final String? stored = await storage.readDek();
  if (stored != null) {
    // Present key: base64-decode and inject. A wrong-length stored value is a
    // corrupt Keystore entry; surface it (Rust's set_history_dek would reject
    // it anyway with a length error, but failing here gives a clearer cause).
    final Uint8List bytes = base64Decode(stored);
    if (bytes.length != _dekLength) {
      throw StateError(
        'history-dek-v1: stored DEK has wrong length '
        '${bytes.length} (expected $_dekLength)',
      );
    }
    await setHistoryDek(bytes);
    return MobileDekResolution.loaded;
  }

  // No stored DEK. If the DB already exists, fail closed -- minting a fresh
  // DEK here would orphan all persisted history (the existing rows are
  // encrypted under a DEK we no longer have). Mirrors Rust's open() guard.
  if (dbExists()) {
    throw StateError(
      'history-dek-v1: DEK absent from Keystore but history DB exists; '
      'refusing to mint a fresh DEK that would orphan persisted history',
    );
  }

  // First run: mint 32 random bytes, base64-encode + write to the Keystore,
  // then inject. The write happens BEFORE the inject so a crash between the
  // two never leaves Rust with a DEK the Keystore does not also have.
  final Uint8List dek = Uint8List.fromList(mint());
  if (dek.length != _dekLength) {
    throw StateError(
      'minted DEK has wrong length ${dek.length} (expected $_dekLength)',
    );
  }
  await storage.writeDek(base64Encode(dek));
  await setHistoryDek(dek);
  return MobileDekResolution.minted;
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

/// Initialize the mobile at-rest DEK. Called from `main()` AFTER
/// `RustLib.init()` and BEFORE `runApp`, gated `if (Platform.isAndroid)`.
/// Desktop and iOS are no-op stubs (they keep the Rust desktop keychain path)
/// so startup is never blocked off-Android.
Future<void> initMobileDek() async {
  if (!Platform.isAndroid) {
    // Desktop (Windows/macOS/Linux) and iOS keep using Rust's
    // OsSecureSecretStore via Persistence::open; no DEK injection.
    return;
  }
  await resolveHistoryDek(
    storage: _FlutterSecureStorageDek(),
    dbExists: () => _historyRedbPath().existsSync(),
    setHistoryDek: (List<int> dek) => api.setHistoryDek(dek: dek),
  );
}
