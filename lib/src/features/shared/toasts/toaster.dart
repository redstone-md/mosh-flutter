import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a toast reports. Errors stay longer and interrupt a screen reader.
enum ToastKind { info, success, error }

/// One shown toast. [bumps] counts repeats folded into it.
@immutable
class ToastEntry {
  const ToastEntry._(this.id, this.message, this.kind, this.bumps);

  final int id;
  final String message;
  final ToastKind kind;
  final int bumps;

  ToastEntry _bumped() => ToastEntry._(id, message, kind, bumps + 1);
}

/// The app's one stack of toasts.
///
/// At most [visible] toasts show, newest first. A new one pushes the
/// oldest out only once that one has been readable for [minShown];
/// otherwise it waits, so a burst never loses a message. Repeating a
/// shown message brings it back to the front instead of stacking a copy. Timers pause
/// while the pointer holds the stack.
class Toaster extends ChangeNotifier {
  Toaster({
    this.visible = 3,
    this.minShown = const Duration(milliseconds: 1500),
    Duration Function(ToastKind kind)? lifetime,
  }) : _lifetime = lifetime ?? _defaultLifetime;

  final int visible;
  final Duration minShown;
  final Duration Function(ToastKind kind) _lifetime;

  final List<ToastEntry> _shown = [];
  final Queue<ToastEntry> _waiting = Queue();
  final Map<int, _Countdown> _countdowns = {};
  int _nextId = 0;
  bool _paused = false;

  /// Shown toasts, newest first.
  List<ToastEntry> get toasts => List.unmodifiable(_shown);

  static Duration _defaultLifetime(ToastKind kind) => kind == ToastKind.error
      ? const Duration(seconds: 6)
      : const Duration(seconds: 4);

  void show(String message, {ToastKind kind = ToastKind.info}) {
    final index =
        _shown.indexWhere((t) => t.message == message && t.kind == kind);
    if (index >= 0) {
      // A repeat comes back to the front, where it can be seen.
      final bumped = _shown.removeAt(index)._bumped();
      _shown.insert(0, bumped);
      _countdowns[bumped.id]!.restart(_lifetime(kind));
      notifyListeners();
      return;
    }
    if (_waiting.any((t) => t.message == message && t.kind == kind)) return;
    _waiting.add(ToastEntry._(_nextId++, message, kind, 0));
    _promote();
  }

  void dismiss(int id) {
    final index = _shown.indexWhere((t) => t.id == id);
    if (index < 0) return;
    _shown.removeAt(index);
    _countdowns.remove(id)?.cancel();
    _promote();
    notifyListeners();
  }

  /// Drops every toast, shown or waiting, as when nothing shows them.
  void clear() {
    for (final countdown in _countdowns.values) {
      countdown.cancel();
    }
    _countdowns.clear();
    _waiting.clear();
    if (_shown.isEmpty) return;
    _shown.clear();
    notifyListeners();
  }

  /// Holds every countdown, as while the stack is fanned out.
  set paused(bool value) {
    if (_paused == value) return;
    _paused = value;
    for (final countdown in _countdowns.values) {
      countdown.paused = value;
    }
  }

  void _promote() {
    var changed = false;
    while (_waiting.isNotEmpty) {
      if (_shown.length >= visible) {
        final oldest = _countdowns[_shown.last.id]!;
        if (!oldest.readable) {
          oldest.onReadable(_promote);
          break;
        }
        _countdowns.remove(_shown.removeLast().id)?.cancel();
      }
      final next = _waiting.removeFirst();
      _shown.insert(0, next);
      _countdowns[next.id] = _Countdown(
          _lifetime(next.kind), () => dismiss(next.id),
          readableAfter: minShown)
        ..paused = _paused;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    for (final countdown in _countdowns.values) {
      countdown.cancel();
    }
    super.dispose();
  }
}

/// A toast's lifetime. Pausing holds it; resuming grants a full lifetime
/// again, so a toast never vanishes right after the pointer lets go.
/// Fake-async friendly: only timers, no wall clock.
class _Countdown {
  _Countdown(this._lifetime, this._onDone, {required Duration readableAfter}) {
    _readable = Timer(readableAfter, () {
      readable = true;
      final then = _onReadable;
      _onReadable = null;
      then?.call();
    });
    _run();
  }

  Duration _lifetime;
  final VoidCallback _onDone;
  late final Timer _readable;
  Timer? _timer;
  bool _paused = false;
  VoidCallback? _onReadable;

  /// Whether the toast has been on screen long enough to read.
  bool readable = false;

  void _run() {
    _timer?.cancel();
    _timer = _paused ? null : Timer(_lifetime, _onDone);
  }

  set paused(bool value) {
    if (_paused == value) return;
    _paused = value;
    _run();
  }

  void restart(Duration lifetime) {
    _lifetime = lifetime;
    _run();
  }

  /// Calls [then] once the toast is [readable].
  void onReadable(VoidCallback then) => _onReadable = then;

  void cancel() {
    _timer?.cancel();
    _readable.cancel();
  }
}

final toasterProvider = Provider<Toaster>((ref) {
  final toaster = Toaster();
  ref.onDispose(toaster.dispose);
  return toaster;
});

extension ToasterContext on BuildContext {
  /// The app's toaster. Read it before an `await` and show afterwards:
  /// the toaster outlives the screen, the context may not.
  Toaster get toaster =>
      ProviderScope.containerOf(this, listen: false).read(toasterProvider);
}
