import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'call_view_state.dart';
import 'call_video_frame.dart';

abstract interface class CallWindowHandle {
  Future<void> present(CallViewState state);
  Future<void> show();
  Future<bool> isFocused();
  Future<void> close();
}

abstract interface class CallWindowFrameSink {
  bool presentFrame(CallVideoFrame frame);
}

abstract interface class CallWindowLifecycle {
  Future<void> get closed;
}

typedef CallWindowFactory = Future<CallWindowHandle> Function(
    Future<void> Function(CallViewCommand) onCommand);

final callWindowFactoryProvider = Provider<CallWindowFactory?>((ref) => null);

/// Serializes window creation, presentation and closure. A window whose startup
/// finishes after the call ended is closed before it receives display data.
class CallWindowCoordinator {
  CallWindowCoordinator(this.factory, this.onCommand, this.onFailure);

  final CallWindowFactory? factory;
  final Future<void> Function(CallViewCommand) onCommand;
  final void Function(Object) onFailure;
  final _available = ValueNotifier(false);
  ValueListenable<bool> get available => _available;
  // Inline controls exist only without a window or after its failure, so a
  // starting window never flashes them.
  late final _fallback = ValueNotifier(factory == null);
  ValueListenable<bool> get fallback => _fallback;
  CallWindowHandle? _window;
  CallViewState? _desired;
  Future<void>? _working;
  int _revision = 0;
  int _presented = 0;
  bool _disposed = false;
  // A renderer that failed for this call is restored only by an explicit
  // show(); otherwise every media update would relaunch a crashing process.
  ({String? session, String? call})? _failed;

  void update(CallViewState? state) {
    if (_disposed || mapEquals(_desired?.toMap(), state?.toMap())) return;
    if (!_isDesiredCall(state)) {
      _available.value = false;
      if (factory != null) _fallback.value = false;
    }
    _desired = state;
    ++_revision;
    _start();
  }

  bool _isDesiredCall(CallViewState? state) =>
      state?.sessionId == _desired?.sessionId &&
      state?.callId == _desired?.callId;

  bool presentFrame(CallVideoFrame frame) {
    final call = _desired;
    if (_disposed ||
        _working != null ||
        call == null ||
        call.sessionId != frame.sessionId ||
        call.callId != frame.callId) {
      return false;
    }
    return switch (_window) {
      CallWindowFrameSink sink => sink.presentFrame(frame),
      _ => false,
    };
  }

  void _start() {
    if (_working != null || factory == null) return;
    _working = _sync().whenComplete(() {
      _working = null;
      if (_presented != _revision) _start();
    });
  }

  Future<void> _sync() async {
    while (_presented != _revision) {
      final revision = _revision;
      final target = _desired;
      try {
        if (_desired == null) {
          final window = _window;
          _window = null;
          _available.value = false;
          await window?.close();
        } else if (_window == null && _hasFailed(_desired)) {
          _available.value = false;
        } else {
          _window ??= _watch(await factory!((command) async {
            final current = _desired;
            if (_disposed ||
                current == null ||
                !command.matchesCall(current.sessionId, current.callId,
                    supersededCallId: current.supersededCallId)) {
              return;
            }
            await onCommand(command);
          }));
          final current = _desired;
          if (current != null && !_disposed) {
            final window = _window!;
            await window.present(current);
            _available.value = !_disposed &&
                identical(_window, window) &&
                _isDesiredCall(current);
            if (_available.value) _fallback.value = false;
          }
        }
      } catch (error) {
        final window = _window;
        _window = null;
        _available.value = false;
        _markFailed(target);
        try {
          await window?.close();
        } catch (_) {
          // The application strip remains usable after a window failure.
        }
        if (!_disposed) onFailure(error);
      }
      _presented = revision;
    }
  }

  CallWindowHandle _watch(CallWindowHandle window) {
    if (window case CallWindowLifecycle lifecycle) {
      unawaited(lifecycle.closed.then((_) async {
        if (_disposed || !identical(_window, window)) return;
        _window = null;
        _available.value = false;
        _markFailed(_desired);
        try {
          await window.close();
        } catch (_) {/* The child may already be gone. */}
        if (!_disposed) onFailure(StateError('Call window exited'));
      }));
    }
    return window;
  }

  bool _hasFailed(CallViewState? state) =>
      _failed == (session: state?.sessionId, call: state?.callId);

  void _markFailed(CallViewState? state) {
    _failed = (session: state?.sessionId, call: state?.callId);
    if (!_disposed && _isDesiredCall(state)) _fallback.value = true;
  }

  Future<void> show() async {
    if (_disposed || _desired == null) return;
    await _working;
    if (_disposed || _desired == null) return;
    if (_window == null) {
      _failed = null;
      ++_revision;
      _start();
      await _working;
    }
    final attempted = _window;
    try {
      await attempted?.show();
    } catch (error) {
      if (_disposed || !identical(_window, attempted)) return;
      _window = null;
      _available.value = false;
      _fallback.value = true;
      try {
        await attempted?.close();
      } catch (_) {/* The native owner may already be gone. */}
      if (!_disposed) {
        onFailure(error);
        ++_revision;
        _start();
        await _working;
      }
    }
  }

  Future<bool> isFocused() async {
    await _working;
    final window = _window;
    if (_disposed || window == null) return false;
    try {
      final focused = await window.isFocused();
      return !_disposed && identical(_window, window) && focused;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _desired = null;
    ++_revision;
    _start();
    await _working;
    _available.dispose();
    _fallback.dispose();
  }
}
