// Slice-3 voice-call: incoming-call OS notification when the window is
// unfocused (1-в-1 port of React private-dm/voice-call/use-voice-call-
// orchestration.ts L250-275 -- the second `useEffect` that fires a Tauri
// sendNotification when a NEW pendingCall appears AND the window is
// unfocused AND notificationsReady() is true). The Flutter side fires an
// OS toast via flutter_local_notifications; the focus check is
// window_manager.isFocused() (Windows/macOS; Linux is undocumented so the
// gate always notifies there, matching React's "always notify on Linux"
// fallback). The in-app IncomingCallModal is the user's signal regardless
// (mirrors React's catch {}).
//
// ADR 0010: notificationsReadyProvider is the Riverpod mirror of React's
// `notificationsReady()` ref-gate -- a FutureProvider<bool> that initializes
// the plugin once at startup and resolves true/false. The voice-call layer
// reads it via `ref.read(notificationsReadyProvider).value == true`.
// The plugin instance is itself a Provider (flutterLocalNotificationsPluginProvider)
// so tests inject a recording fake -- the same seam convention as
// gatewayProvider / voiceCaptureFactoryProvider / voicePlaybackFactoryProvider.
library;

import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Mosh's Windows toast identity. The AUMID must be registered with a Start
// Menu shortcut for toasts to surface (classic Windows toast requirement);
// the shortcut registration is a separate installer/first-run atom (the
// win32_registry dep can do it). The GUID is a fixed per-app identifier.
const _kWindowsAumid = 'redstone.md.Mosh.MoshClient.1';
const _kWindowsGuid = '8f2c3d4e-5a6b-4c7d-9e8f-0a1b2c3d4e5f';

const moshNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'mosh_notifications',
    'Mosh notifications',
    channelDescription: 'Messages and incoming calls',
    importance: Importance.high,
    priority: Priority.high,
  ),
);

enum MoshNotificationPlatform { android, ios, macos, linux, windows, other }

final notificationPlatformProvider = Provider<MoshNotificationPlatform>((ref) {
  if (Platform.isAndroid) return MoshNotificationPlatform.android;
  if (Platform.isIOS) return MoshNotificationPlatform.ios;
  if (Platform.isMacOS) return MoshNotificationPlatform.macos;
  if (Platform.isLinux) return MoshNotificationPlatform.linux;
  if (Platform.isWindows) return MoshNotificationPlatform.windows;
  return MoshNotificationPlatform.other;
});

typedef AndroidNotificationPermissionRequest = Future<bool?> Function(
  FlutterLocalNotificationsPlugin plugin,
);

final androidNotificationPermissionProvider =
    Provider<AndroidNotificationPermissionRequest>((ref) => (plugin) async {
          return plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission();
        });

/// The single flutter_local_notifications plugin instance, exposed as a
/// Provider so tests override it with a recording fake (the seam
/// convention). The default body calls the plugin's singleton factory --
/// `FlutterLocalNotificationsPlugin()` returns the same instance every
/// time, but overriding the Provider with `overrideWith((ref) => fake)`
/// swaps the value the rest of the app reads.
final flutterLocalNotificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>(
  (ref) => FlutterLocalNotificationsPlugin(),
);

/// notificationsReadyProvider -- the init + permission gate for the
/// incoming call OS notification, 1-в-1 with React's `notificationsReady()`
/// ref. Runs the flutter_local_notifications init once at startup; on
/// macOS/iOS requests alert/badge/sound permission; on Windows/Linux no
/// permission prompt. Resolves false on host-unavailable (the in-app
/// IncomingCallModal is the user's signal regardless). Read via
/// `ref.watch(notificationsReadyProvider).value == true` from the
/// voice-call layer.
final notificationsReadyProvider = FutureProvider<bool>((ref) async {
  final plugin = ref.watch(flutterLocalNotificationsPluginProvider);
  final platform = ref.watch(notificationPlatformProvider);
  try {
    final initialized = await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_mosh'),
        windows: WindowsInitializationSettings(
          appName: 'Mosh',
          appUserModelId: _kWindowsAumid,
          guid: _kWindowsGuid,
        ),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      ),
    );
    if (initialized != true) return false;
    if (platform == MoshNotificationPlatform.android) {
      final ok = await ref
          .read(androidNotificationPermissionProvider)(plugin);
      return ok ?? false;
    }
    if (platform == MoshNotificationPlatform.macos) {
      final ok = await plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return ok ?? false;
    }
    if (platform == MoshNotificationPlatform.ios) {
      final ok = await plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return ok ?? false;
    }
    return true; // Windows/Linux: no permission prompt
  } catch (_) {
    return false; // host unavailable / init failed -> in-app modal is the signal
  }
});
