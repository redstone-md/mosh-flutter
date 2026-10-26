import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'android_access_state.dart';

final androidAppAccessProvider = Provider<AndroidAppAccess?>((ref) => null);

/// Mirrors the installation-owned native policy; a call never grants chat access.
class AndroidAppAccess extends ChangeNotifier {
  AndroidAppAccess() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'accessStateChanged') _accept(call.arguments);
    });
  }
  static const channel = MethodChannel('app.mosh.mosh/access');
  AndroidAccessState? _state;
  int _revision = -1;
  int? _shieldGeneration;
  bool _failed = false, _disposed = false, _visible = false, _marking = false;
  int _authentication = 0;
  Future<void> _writes = Future.value();
  AndroidAccessState? get state => _state;
  bool get covered =>
      _failed || _state?.allowed != true || _state?.deviceInteractive != true;
  bool get chatsInteractive =>
      !covered && _state!.deviceInteractive && _visible;
  bool get failed => _failed;
  int get delaySeconds => _state?.delaySeconds ?? 60;

  Future<void> initialize() => refresh();

  Future<void> refresh() async {
    try {
      _accept(await channel.invokeMethod<Object?>('readAccessState'));
    } catch (_) {
      _fail();
    }
  }

  void _accept(Object? value) {
    if (_disposed) return;
    try {
      final map = value as Map<Object?, Object?>;
      final revision = map['revision'] as int;
      if (revision < _revision) return;
      _revision = revision;
      _shieldGeneration = map['shieldGeneration'] as int?;
      _failed = map['error'] == true;
      if (!_failed) _state = AndroidAccessState.fromMap(map);
      notifyListeners();
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    if (_disposed) return;
    _failed = true;
    notifyListeners();
  }

  Future<void> authenticate(String reason) async {
    final request = ++_authentication;
    final result = await channel
        .invokeMethod<String>('authenticateChats', {'reason': reason});
    if (_disposed || request != _authentication) {
      throw PlatformException(code: 'AUTHENTICATION_CANCELED');
    }
    if (result != 'authenticated') {
      throw PlatformException(
          code: result == 'canceled'
              ? 'AUTHENTICATION_CANCELED'
              : 'AUTHENTICATION_UNAVAILABLE');
    }
    await refresh();
    if (covered) throw PlatformException(code: 'ACCESS_STATE_UNAVAILABLE');
  }

  Future<void> setDelay(int seconds) async {
    if (!AndroidAccessState.delays.contains(seconds)) {
      throw ArgumentError.value(seconds, 'seconds');
    }
    await _save(delay: seconds);
  }

  Future<void> _save({int? delay, String? phase}) {
    final work = _writes.then((_) async {
      if (_disposed) return;
      final state = _state;
      if (state == null) throw StateError('Access state unavailable');
      try {
        _accept(await channel.invokeMethod<Object?>(
            'saveAccessState', state.record(delay: delay, phase: phase)));
      } catch (_) {
        _fail();
        rethrow;
      }
    });
    _writes = work.catchError((Object _) {});
    return work;
  }

  void setChatVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    if (!visible && !covered && _state!.state == 'interactive') {
      unawaited(_save(phase: 'grace').catchError((_) {}));
    }
  }

  /// Called after protected UI paints, never by notification/call actions.
  Future<void> protectedFrameReady() async {
    if (_disposed) return;
    final generation = _shieldGeneration;
    if (generation != null) {
      try {
        await channel.invokeMethod<void>('protectedFrameReady',
            {'generation': generation, 'chatsVisible': !covered});
      } catch (_) {/* A detached window needs no acknowledgement. */}
    }
    if (chatsInteractive && _state!.state == 'grace' && !_marking) {
      _marking = true;
      try {
        await _save(phase: 'interactive');
      } catch (_) {/* The write already covered the UI on failure. */} finally {
        _marking = false;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _authentication++;
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}
