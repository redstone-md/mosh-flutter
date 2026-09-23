// The mic-permission platform config, pinned by tests.
//
// The 0.9.1 macOS crash reports (.ips, TCC namespace): opening a chat
// called the mic permission probe at mount, and with no
// NSMicrophoneUsageDescription in the macOS plist TCC killed the process
// before any dialog appeared. The same key is required on iOS, the
// sandboxed macOS app additionally needs the audio-input entitlement, and
// Android needs RECORD_AUDIO declared. These assertions keep the keys
// from silently disappearing in a future refactor — the failure mode is
// a crash on device, not in CI, so the suite is the only place it can be
// caught early.
//
// Real files, no fixtures: the test reads the shipped config, so drift
// between the repo and the assertion is impossible.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Minimal XML key/value extraction: returns the `string` body that
/// follows a `key` element with [name]. Plists here are flat key-value
/// pairs, so no full DOM is needed — but a missing key must return null,
/// not "".
String? plistValue(String xml, String name) {
  final i = xml.indexOf('<key>$name</key>');
  if (i < 0) return null;
  final rest = xml.substring(i + name.length + 13); // len('<key></key>')
  final match =
      RegExp(r'<string>(.*?)</string>', dotAll: true).firstMatch(rest);
  return match?.group(1)?.trim();
}

void main() {
  group('macOS', () {
    final plist = File('macos/Runner/Info.plist').readAsStringSync();

    test('Info.plist carries NSMicrophoneUsageDescription', () {
      final usage = plistValue(plist, 'NSMicrophoneUsageDescription');
      expect(usage, isNotNull,
          reason: 'TCC kills the process at the mic request without it');
      expect(usage!.toLowerCase(), contains('microphone'));
    });

    for (final entry in const [
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      test('$entry allows audio input (sandbox entitlement)', () {
        final xml = File(entry).readAsStringSync();
        expect(
            xml, contains('<key>com.apple.security.device.audio-input</key>'),
            reason: 'a sandboxed app without it is silently mic-denied');
        // The key must be followed by <true/> within the next few chars.
        final i =
            xml.indexOf('<key>com.apple.security.device.audio-input</key>');
        expect(xml.substring(i, i + 80), contains('<true/>'));
      });
    }
  });

  test('iOS Info.plist carries NSMicrophoneUsageDescription', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final usage = plistValue(plist, 'NSMicrophoneUsageDescription');
    expect(usage, isNotNull,
        reason: 'iOS shows the same TCC crash as macOS without it');
    expect(usage!.toLowerCase(), contains('microphone'));
  });

  test('Android manifest declares RECORD_AUDIO', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      manifest,
      contains('android.permission.RECORD_AUDIO'),
      reason: 'the runtime request needs the declared permission; '
          'the plugin merge alone is fragile',
    );
  });
}
