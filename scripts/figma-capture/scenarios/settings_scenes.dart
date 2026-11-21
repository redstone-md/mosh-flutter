// Settings area scenes: navigation, every section and its states, About's
// update states, the Android-only cards, and the diagnostics drawer/details.
// settings_test.dart runs them on the phone, settings_desktop_test.dart on the
// desktop (each in its own isolate, so the app theme is built per platform).
import 'dart:io';

import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:mosh/src/app/bundled_licenses.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/distribution_channel.dart';
import 'package:mosh/src/app/distribution_channel_provider.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/features/crash_reporting/crash_reporting.dart';
import 'package:mosh/src/features/diagnostics/field_log_button.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/features/settings/about_update_notice.dart';
import 'package:mosh/src/features/settings/app_release_provider.dart';
import 'package:mosh/src/features/settings/app_update_apply.dart';
import 'package:mosh/src/features/settings/app_update_install.dart';
import 'package:mosh/src/features/settings/settings_navigation.dart';
import 'package:mosh/src/rust/vpn_consent.dart';
import 'package:mosh/src/state/audio_device_picks_provider.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../../test/support/first_run.dart';
import '../../../test/support/scriptable_bridge.dart';
import '../../../test/support/settings.dart';
import '../../../test/support/update_assets.dart';
import 'harness.dart';
import 'settings_android.dart';
import 'settings_diagnostics.dart';
import 'settings_support.dart';

const _sound = SettingsSection.sound;
const _profile = SettingsSection.profile;
const _connection = SettingsSection.connection;
const _privacy = SettingsSection.privacy;
const _about = SettingsSection.about;

Finder _select<T>() => find.byType(MoshSelect<T>);

/// Opens the first [MoshSelect] of type [T]: a menu on desktop, a sheet on
/// the phone.
Future<void> _openSelect<T>(WidgetTester tester, {int index = 0}) async {
  await tapVisible(tester, _select<T>().at(index));
}

final _crashAvailable = crashReportingProvider.overrideWith((ref) =>
    CrashReporting(
        bridge: ref.watch(bridgeFacadeProvider),
        dsn: 'https://public@crash.example/1',
        start: (_, __) async {},
        stop: () async {},
        capture: (_) {}));

/// About with a newer release on the feed; [host] decides whether the notice
/// offers Update (Windows) or the release page (other hosts).
Future<void> _aboutRelease(WidgetTester tester, Size size,
        {UpdateInstallState? install,
        HostPlatform host = HostPlatform.windows,
        Future<PublishedRelease?> Function()? check}) =>
    mountSettings(tester, size, section: _about, overrides: [
      updateCheckProvider.overrideWith(
          (ref) => check?.call() ?? Future.value(releaseWithAssets())),
      hostPlatformProvider.overrideWithValue(host),
      updateApplierProvider.overrideWithValue(WindowsUpdateApplier(
          start: (_, __, ___) async {}, terminate: (_) {})),
      if (install != null)
        updateInstallProvider.overrideWith(() => FixedInstall(install)),
    ]);

/// Scene order is the Figma order; both entry points keep every scene so the
/// output indexes match across devices.
final settingsScenes = <FigmaScene>[
  // Navigation
  FigmaScene('nav', 'Settings / Navigation / Sections', (tester, size) async {
    await mountSettings(tester, size);
  }, devices: [FigmaDevice.mobile]),

  // Sound & Video
  FigmaScene('sound', 'Settings / Sound & Video / Default',
      (tester, size) async {
    await mountSettings(tester, size, section: _sound);
  }),
  FigmaScene(
      'sound-mic-menu', 'Settings / Sound & Video / Microphone picker open',
      (tester, size) async {
    await mountSettings(tester, size, section: _sound);
    await _openSelect<String?>(tester);
  }),
  FigmaScene('sound-loading', 'Settings / Sound & Video / Devices loading',
      (tester, size) async {
    await mountSettings(tester, size, section: _sound, inputs: never);
  }),
  FigmaScene(
      'sound-load-error', 'Settings / Sound & Video / Devices failed to load',
      (tester, size) async {
    await mountSettings(tester, size,
        section: _sound,
        inputs: () async => throw StateError('no audio service'));
  }),
  FigmaScene('sound-device-missing',
      'Settings / Sound & Video / Saved device unavailable',
      (tester, size) async {
    await mountSettings(tester, size,
        section: _sound,
        picks: MemoryAudioPicks(
            const AudioDevicePicks(inputDeviceId: 'jabra-evolve-65')));
  }),
  FigmaScene('sound-testing', 'Settings / Sound & Video / Test sound playing',
      (tester, size) async {
    await mountSettings(tester, size, section: _sound);
    await tapVisible(tester, find.text(l10n.settingsTestRingtone),
        settle: false);
  }),
  FigmaScene('sound-test-error', 'Settings / Sound & Video / Test sound failed',
      (tester, size) async {
    await mountSettings(tester, size,
        section: _sound,
        ringtone: RecordingSettingsRingtone()..failStart = true);
    await tapVisible(tester, find.text(l10n.settingsTestRingtone));
  }),
  FigmaScene('sound-save-error', 'Settings / Sound & Video / Choice not saved',
      (tester, size) async {
    await mountSettings(tester, size,
        section: _sound, picks: MemoryAudioPicks()..failWrite = true);
    await _openSelect<String?>(tester);
    await tester.tap(find.text('USB microphone').last);
    await tester.pumpAndSettle();
  }),

  // Profile
  FigmaScene('profile', 'Settings / Profile / Default', (tester, size) async {
    await mountSettings(tester, size, section: _profile);
  }),
  FigmaScene(
      'profile-language-menu', 'Settings / Profile / Language picker open',
      (tester, size) async {
    await mountSettings(tester, size, section: _profile);
    await _openSelect<Locale?>(tester);
  }),
  FigmaScene('profile-name-saved', 'Settings / Profile / Name saved',
      (tester, size) async {
    await mountSettings(tester, size, section: _profile);
    await tester.enterText(find.byType(TextFormField), 'Alex R.');
    await tapVisible(tester, find.text(l10n.firstRunSaveName));
  }),
  FigmaScene(
      'profile-read-error', 'Settings / Profile / Profile failed to load',
      (tester, size) async {
    await mountSettings(tester, size, section: _profile, overrides: [
      firstRunStoreProvider.overrideWithValue(MemoryFirstRunStore(
          const FirstRunProfile(displayName: 'Alex Rivera', completed: true))
        ..readError = const FormatException('corrupt')),
    ]);
  }),

  // Connection
  FigmaScene('connection', 'Settings / Connection / Default',
      (tester, size) async {
    await mountSettings(tester, size, section: _connection);
  }),
  FigmaScene('connection-vpn', 'Settings / Connection / VPN bypass expanded',
      (tester, size) async {
    await mountSettings(tester, size, section: _connection);
    await tapVisible(tester, find.text(l10n.settingsVpnTitle));
  }),
  FigmaScene(
      'connection-vpn-menu', 'Settings / Connection / Adapter picker open',
      (tester, size) async {
    await mountSettings(tester, size, section: _connection);
    await tapVisible(tester, find.text(l10n.settingsVpnTitle));
    await _openSelect<String>(tester);
  }),
  FigmaScene('connection-vpn-restart',
      'Settings / Connection / VPN bypass saved, restart needed',
      (tester, size) async {
    await mountSettings(tester, size, section: _connection);
    await tapVisible(tester, find.text(l10n.settingsVpnTitle));
    await tapVisible(tester, find.byType(Switch).first);
  }),
  FigmaScene('connection-vpn-bound', 'Settings / Connection / VPN bypass on',
      (tester, size) async {
    final bridge = settingsBridge()
      ..seedVpnConsent(
          const VpnBypassConsent(interface_: 'Ethernet', index: 4));
    await mountSettings(tester, size, section: _connection, bridge: bridge);
    await tapVisible(tester, find.text(l10n.settingsVpnTitle));
  }),
  FigmaScene('connection-vpn-no-adapter',
      'Settings / Connection / No adapter to bypass with',
      (tester, size) async {
    final bridge = settingsBridge()..seedInterfaces(const [vpnTunnel]);
    await mountSettings(tester, size, section: _connection, bridge: bridge);
    await tapVisible(tester, find.text(l10n.settingsVpnTitle));
  }),
  FigmaScene(
      'connection-vpn-error', 'Settings / Connection / Adapters failed to load',
      (tester, size) async {
    final bridge = settingsBridge()..failAlways(BridgeMethod.listInterfaces);
    await mountSettings(tester, size, section: _connection, bridge: bridge);
    await tapVisible(tester, find.text(l10n.settingsVpnTitle));
  }),
  ...androidConnectionScenes,

  // Privacy
  FigmaScene('privacy', 'Settings / Privacy / Default', (tester, size) async {
    await mountSettings(tester, size,
        section: _privacy, overrides: [_crashAvailable]);
  }),
  FigmaScene('privacy-details', 'Settings / Privacy / Details expanded',
      (tester, size) async {
    await mountSettings(tester, size,
        section: _privacy, overrides: [_crashAvailable]);
    await tapVisible(tester, find.text(l10n.settingsCrashReportsDetailsTitle));
    await tapVisible(tester, find.text(l10n.settingsReadReceiptsDetailsTitle));
  }),
  FigmaScene('privacy-on', 'Settings / Privacy / Crash reports and receipts on',
      (tester, size) async {
    final bridge = settingsBridge()
      ..seedCrashReportingSalt('salt')
      ..seedReadReceiptsEnabled(true);
    await mountSettings(tester, size,
        section: _privacy, bridge: bridge, overrides: [_crashAvailable]);
  }),
  FigmaScene('privacy-crash-unavailable',
      'Settings / Privacy / Crash reports unavailable in this build',
      (tester, size) async {
    await mountSettings(tester, size, section: _privacy);
  }),
  ...androidPrivacyScenes,

  // About
  FigmaScene('about', 'Settings / About / Up to date', (tester, size) async {
    await _aboutRelease(tester, size, check: () async => null);
  }),
  FigmaScene('about-checking', 'Settings / About / Checking for updates',
      (tester, size) async {
    await _aboutRelease(tester, size, check: never);
  }),
  FigmaScene('about-check-failed', 'Settings / About / Update check failed',
      (tester, size) async {
    await _aboutRelease(tester, size,
        check: () async => throw StateError('feed unavailable'));
  }),
  FigmaScene('about-update', 'Settings / About / Update available',
      (tester, size) async {
    await _aboutRelease(tester, size);
  }),
  FigmaScene('about-update-page',
      'Settings / About / Update available, release page only',
      (tester, size) async {
    await _aboutRelease(tester, size, host: HostPlatform.other);
  }),
  FigmaScene('about-downloading', 'Settings / About / Downloading update',
      (tester, size) async {
    await _aboutRelease(tester, size,
        install: const UpdateInstallDownloading(
            received: 38 << 20, total: 61 << 20));
  }),
  FigmaScene('about-installing', 'Settings / About / Installing and restarting',
      (tester, size) async {
    await _aboutRelease(tester, size, install: const UpdateInstallApplying());
  }),
  FigmaScene('about-image-open', 'Settings / About / macOS image opened',
      (tester, size) async {
    await _aboutRelease(tester, size,
        host: HostPlatform.macOS,
        install: const UpdateInstallImageOpen(),
        check: () async => releaseWithAssets(assetNames: const [
              'Mosh_0.22.0_universal.dmg',
              'Mosh_0.22.0_universal.dmg.sha256',
            ]));
  }),
  FigmaScene('about-install-failed', 'Settings / About / Update failed',
      (tester, size) async {
    await _aboutRelease(tester, size, install: const UpdateInstallFailed());
  }),
  FigmaScene('about-store', 'Settings / About / Store build',
      (tester, size) async {
    await mountSettings(tester, size, section: _about, overrides: [
      distributionChannelProvider
          .overrideWithValue(DistributionChannel.msstore),
    ]);
  }),
  FigmaScene(
      'about-open-failed', 'Settings / About / Release page did not open',
      (tester, size) async {
    await mountSettings(tester, size, section: _about, overrides: [
      updateCheckProvider.overrideWith((ref) async => releaseWithAssets()),
      releasePageOpenerProvider.overrideWithValue((_) async => false),
    ]);
    await tapVisible(tester, find.text(l10n.settingsAboutUpdateOpen),
        settle: false);
  }),
  FigmaScene('about-log-empty', 'Settings / About / App log empty',
      (tester, size) async {
    await mountSettings(tester, size, section: _about, overrides: [
      fieldLogExportProvider.overrideWithValue(() async => null)
    ]);
    await tapVisible(tester, find.text(l10n.fieldLogShare));
  }),
  FigmaScene('about-log-failed', 'Settings / About / App log not shared',
      (tester, size) async {
    await mountSettings(tester, size, section: _about, overrides: [
      fieldLogExportProvider.overrideWithValue(
          () async => throw const FileSystemException('disk full')),
    ]);
    await tapVisible(tester, find.text(l10n.fieldLogShare));
  }),
  FigmaScene('about-licenses', 'Settings / About / Open source licenses',
      (tester, size) async {
    // main registers the bundled notices; the scene does what main does.
    LicenseRegistry.addLicense(bundledLicenses);
    await mountSettings(tester, size, section: _about);
    await tapVisible(tester, find.text(l10n.settingsAboutLicenses),
        settle: false);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 200));
    }
  }),

  // Diagnostics
  ...diagnosticsScenes,
];
