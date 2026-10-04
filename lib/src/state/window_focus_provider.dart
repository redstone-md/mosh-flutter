import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:window_manager/window_manager.dart' show windowManager;

/// Default focus check: `windowManager.isFocused()` with a try/catch that
/// degrades to `true` (focused) on error. Exposed as a top-level function
/// so the provider body + tests share one reference and the override site
/// reads cleanly.
Future<bool> _defaultIsFocused() async {
  try {
    return await windowManager.isFocused();
  } catch (_) {
    // No window_manager host (browser dev / a test without the platform
    // plugin): treat as focused so the badge clears + no toast fires.
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
