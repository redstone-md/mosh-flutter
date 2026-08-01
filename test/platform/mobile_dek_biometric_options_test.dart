// M-7 config test for the Android Keystore options that gate the at-rest
// history DEK behind user presence (ADR 0011 default-on). Asserts the exact
// biometric config produced by `buildDekAndroidOptions()` via `toMap()` so
// a regression that drops `enforceBiometrics`, swaps the cipher, or loses
// the namespace is caught at host-test time. The decision-logic branches
// (loaded / minted / fail-closed) are covered separately in
// `mobile_dek_test.dart`; this file only pins the storage wiring config.

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/platform/mobile_dek.dart';

void main() {
  test('buildDekAndroidOptions enforces user-presence gating', () {
    final Map<String, String> map = buildDekAndroidOptions().toMap();

    // ADR 0011: fail closed on an insecure device (no PIN/biometric enrolled).
    expect(
      map['enforceBiometrics'],
      'true',
      reason: 'user presence must be enforced, not gracefully degraded',
    );

    // KeyStore-backed AES-GCM is the only key+storage cipher combination
    // that supports `setUserAuthenticationRequired` for biometric gating.
    expect(map['keyCipherAlgorithm'], 'AES_GCM_NoPadding');
    expect(map['storageCipherAlgorithm'], 'AES_GCM_NoPadding');

    // Namespace preserved from M-3 so mobile/desktop sit under `app.mosh.*`.
    expect(map['storageNamespace'], 'app.mosh.mobile');

    // Strong biometric OR PIN/pattern/password -- do NOT lock out PIN-only
    // devices with `strongBiometricOnly`.
    expect(map['biometricType'], 'biometricOrDeviceCredential');

    // BiometricPrompt copy.
    expect(map['biometricPromptTitle'], 'Unlock Mosh');
    expect(
      map['biometricPromptSubtitle'],
      'Authenticate to access your conversations',
    );
    expect(map['biometricPromptNegativeButton'], 'Cancel');
  });
}
