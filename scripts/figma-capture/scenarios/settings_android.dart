// Android-only settings cards: background availability (Connection) and the
// app lock delay (Privacy). Both providers are null off Android, so the
// scenes hand MoshApp real owners over mocked platform channels.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/features/background/android_waiting_owner.dart';
import 'package:mosh/src/features/background/background_commands.dart';
import 'package:mosh/src/features/lock/android_app_access.dart';
import 'package:mosh/src/features/settings/settings_navigation.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:mosh/src/rust/api/background/types.dart';
import 'package:mosh/src/rust/persistence/background_delivery.dart'
    show BackgroundNotification;

import 'harness.dart';
import 'settings_support.dart';

const _phone = [FigmaDevice.mobile];

TestDefaultBinaryMessenger _messenger() =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// Answers every waiting-channel call with one state map; the action queues
/// are empty and the other one-way calls succeed.
void _mockChannel(MethodChannel channel, Map<String, Object?> state) {
  _messenger().setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
            'takeCallActions' || 'takeTransferActions' => const <Object?>[],
            'setMediaTypes' => true,
            'publishNotification' => 'published',
            'acknowledgeTransferActions' => null,
            _ => state,
          });
  addTearDown(() => _messenger().setMockMethodCallHandler(channel, null));
}

Map<String, Object?> _waiting({required bool enabled}) => {
      'revision': 1,
      'intentRevision': 1,
      'interactive': true,
      'waitingEnabled': enabled,
      'serviceRunning': enabled,
      'setupComplete': true,
      'notificationsAllowed': false,
      'batteryExempt': false,
      'fullScreenCallsAllowed': false,
      'showNamesWhenLocked': true,
      'showTextWhenLocked': false,
    };

/// [failed] keeps the failure the background owner reports when its Rust
/// side cannot attach (as here, with no runtime); otherwise it is cleared, as
/// a successful attach would.
/// An installation whose Rust side attached: idle, nothing pending, and an
/// event stream that stays open.
class _AttachedCommands extends BackgroundCommands {
  _AttachedCommands(this.enabled);
  final bool enabled;
  final _changes = StreamController<BigInt>();

  BackgroundStatus get _status => BackgroundStatus(
      revision: BigInt.one,
      interactive: true,
      waitingEnabled: enabled,
      requestedMode: BackgroundMode.offline,
      actualMode: BackgroundMode.offline,
      reachability: BackgroundReachability.ready,
      attachmentCount: 0,
      currentCalls: 0,
      currentUserTransfers: 0,
      userTransfers: const []);

  @override
  Future<BackgroundStatus> setExecution(
          {required bool interactive, required bool waitingEnabled}) async =>
      _status;
  @override
  Future<BackgroundStatus> status() async => _status;
  @override
  Stream<BigInt> changes() => _changes.stream;
  @override
  Future<List<BackgroundNotification>> pending() async => const [];
}

Future<void> _mountWaiting(WidgetTester tester, Size size,
    {required bool enabled, bool failed = false}) async {
  _mockChannel(AndroidWaitingPlatform.channel, _waiting(enabled: enabled));
  final platform = AndroidWaitingPlatform();
  addTearDown(platform.dispose);
  await platform.refresh();
  final owner = AndroidWaitingOwner(
      platform, failed ? BackgroundCommands() : _AttachedCommands(enabled));
  addTearDown(owner.dispose);
  await mountSettings(tester, size,
      section: SettingsSection.connection,
      overrides: [androidWaitingOwnerProvider.overrideWithValue(owner)]);
}

Future<void> _mountAppLock(WidgetTester tester, Size size) async {
  _mockChannel(AndroidAppAccess.channel, {
    'version': 1,
    'delaySeconds': 60,
    'bootCount': 5,
    'deadlineElapsedMs': null,
    'state': 'interactive',
    'elapsedRealtimeMs': 1000,
    'allowed': true,
    'revision': 1,
    'shieldGeneration': 1,
    'deviceInteractive': true,
  });
  final access = AndroidAppAccess();
  addTearDown(access.dispose);
  await access.initialize();
  await mountSettings(tester, size,
      section: SettingsSection.privacy,
      overrides: [androidAppAccessProvider.overrideWithValue(access)]);
}

final androidConnectionScenes = [
  FigmaScene('connection-android-waiting',
      'Settings / Connection / Android background availability',
      (tester, size) async {
    await _mountWaiting(tester, size, enabled: true);
  }, devices: _phone),
  FigmaScene('connection-android-waiting-failed',
      'Settings / Connection / Android background availability failed',
      (tester, size) async {
    await _mountWaiting(tester, size, enabled: true, failed: true);
  }, devices: _phone),
  FigmaScene('connection-android-waiting-off',
      'Settings / Connection / Android background availability off',
      (tester, size) async {
    await _mountWaiting(tester, size, enabled: false);
  }, devices: _phone),
  FigmaScene('connection-android-battery-dialog',
      'Settings / Connection / Background connection explanation dialog',
      (tester, size) async {
    await _mountWaiting(tester, size, enabled: true);
    await tapVisible(tester,
        find.widgetWithText(TextButton, l10n.settingsBackgroundBattery));
  }, devices: _phone),
  FigmaScene('connection-android-calls-dialog',
      'Settings / Connection / Lock screen calls explanation dialog',
      (tester, size) async {
    await _mountWaiting(tester, size, enabled: true);
    await tapVisible(
        tester,
        find.widgetWithText(
            TextButton, l10n.settingsBackgroundFullScreenCalls));
  }, devices: _phone),
];

final androidPrivacyScenes = [
  FigmaScene('privacy-app-lock', 'Settings / Privacy / Android app lock',
      (tester, size) async {
    await _mountAppLock(tester, size);
  }, devices: _phone),
  FigmaScene(
      'privacy-app-lock-menu', 'Settings / Privacy / App lock delay picker',
      (tester, size) async {
    await _mountAppLock(tester, size);
    await tapVisible(tester, find.byType(MoshSelect<int>));
  }, devices: _phone),
];
