// The window-focus seam: a `Provider<Future<bool> Function()>` the
// unread-lifecycle provider reads instead of calling `windowManager`
// directly. Mirrors React's `windowFocused()` helper (use-unread-
// notifications.ts): it awaits `getCurrentWindow().isFocused()` and
// degrades to `true` (focused) on any error so a missing Tauri host or a
// test without a window_manager platform impl keeps the badge clear.
//
// Why a seam instead of `windowManager.isFocused()` inline: the precedent
// (voice_call_layer.dart) calls `windowManager.isFocused()` directly and
// tests mock the 'window_manager' method channel. That works but is noisy
// for a pure provider test. A `Provider<Future<bool> Function()>` is the
// same seam convention as gatewayProvider / notificationsReadyProvider:
// the lifecycle provider depends on it, tests override it with a plain
// `() async => false`/`() async => true` and the focus check becomes
// deterministic without a method-channel mock.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:window_manager/window_manager.dart' show windowManager;

/// Default focus check: `windowManager.isFocused()` with a try/catch that
/// degrades to `true` (focused) on error, 1-1 with React's `windowFocused`.
/// Exposed as a top-level function so the provider body + tests share one
/// reference and the override site reads cleanly.
Future<bool> _defaultIsFocused() async {
  try {
    return await windowManager.isFocused();
  } catch (_) {
    // No window_manager host (browser dev / a test without the platform
    // plugin): treat as focused so the badge clears + no toast fires,
    // matching React's `catch { return true }`.
    return true;
  }
}

/// The focus seam. Reads as `Future<bool> Function()`; the lifecycle
/// provider awaits `ref.read(windowFocusProvider)()`. Tests override with
/// `windowFocusProvider.overrideWithValue(() async => false)` to simulate
/// an unfocused window and `() async => true` for focused.
final windowFocusProvider = Provider<Future<bool> Function()>(
  (ref) => _defaultIsFocused,
);
