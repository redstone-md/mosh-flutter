import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:mosh/src/rust/api/background/types.dart';
import 'background_commands.dart';
import 'background_delivery_pump.dart';
import 'android_background_calls.dart';
import 'background_execution_mirror.dart';

final androidWaitingOwnerProvider =
    Provider<AndroidWaitingOwner?>((ref) => null);

/// Process-owned execution and notification intake, independent of mounted chats.
class AndroidWaitingOwner extends ChangeNotifier {
  AndroidWaitingOwner(this.platform, this.commands) {
    calls = AndroidBackgroundCalls(commands, platform);
    _mirror = BackgroundExecutionMirror(platform);
    delivery = BackgroundDeliveryPump(commands, platform, calls);
    platform.addListener(_platformChanged);
  }
  final AndroidWaitingPlatform platform;
  final BackgroundCommands commands;
  late final BackgroundDeliveryPump delivery;
  late final AndroidBackgroundCalls calls;
  late final BackgroundExecutionMirror _mirror;
  BackgroundStatus? status;
  Object? failure;
  bool _keyReady = false, _setupReady = false, _attached = false;
  bool _disposed = false, _dirty = false;
  Future<void>? _work;
  StreamSubscription<BigInt>? _subscription;
  Object? _appliedExecution;
  bool get attached => _attached;

  /// Foreground setup starts its quiet service before key/network work. A cold
  /// service entry already has one; a saved Stop choice is never changed here.
  Future<void> prepare() async {
    try {
      await platform.refresh();
      final state = platform.state!;
      if (state.setupComplete &&
          state.waitingEnabled &&
          state.interactive &&
          !state.serviceRunning) {
        await platform.enable();
      }
    } catch (error) {
      failure = error;
      notifyListeners();
    }
  }

  /// Called only after the installation's DEK was loaded successfully.
  Future<void> attach({bool setupCompleted = false}) async {
    _keyReady = true;
    await prepare();
    _setupReady |= setupCompleted || platform.state?.setupComplete == true;
    if (!_setupReady) return;
    if (setupCompleted &&
        platform.state?.setupComplete != true &&
        platform.state?.interactive == true) {
      await platform.enable();
    }
    _attached = true;
    _subscription ??= commands.changes().listen(
      (_) => _schedule(),
      onError: (Object error) {
        if (!_disposed) {
          failure = error;
          notifyListeners();
        }
      },
      onDone: () {
        if (!_disposed) {
          _subscription = null;
          failure = StateError('Background event stream closed');
          notifyListeners();
        }
      },
    );
    try {
      await refresh();
    } catch (_) {
      // A permitted cold service must not remain “Connecting” without its
      // installation owner. The saved waiting choice survives this failure.
      await startupFailed('nativeUnavailable');
    }
  }

  Future<void> startupFailed(String reason) async {
    try {
      await platform.startupFailed(reason);
    } catch (error) {
      failure = error;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() {
    _dirty = true;
    final pending = _work;
    if (pending != null) return pending;
    final completion = Completer<void>();
    _work = completion.future;
    unawaited(_run(completion));
    return completion.future;
  }

  void _schedule() {
    if (_disposed || !_keyReady || !_attached) return;
    unawaited(refresh().catchError((Object _) {}));
  }

  Future<void> _run(Completer<void> completion) async {
    try {
      while (_dirty && !_disposed) {
        _dirty = false;
        await _turn();
      }
      completion.complete();
    } catch (error, stack) {
      failure = error;
      notifyListeners();
      completion.completeError(error, stack);
    } finally {
      _work = null;
      if (_dirty && !_disposed) _schedule();
    }
  }

  Future<void> _turn() async {
    final state = platform.state;
    if (!_keyReady || !_attached || !_setupReady) return;
    if (state?.interactive == true && state?.setupComplete != true) {
      await platform.enable();
      _dirty = true;
      return;
    }
    final choice = (
      state?.interactive == true,
      state?.waitingEnabled == true && state?.serviceRunning == true
    );
    if (choice != _appliedExecution) {
      status = await commands.setExecution(
          interactive: choice.$1, waitingEnabled: choice.$2);
      _appliedExecution = choice;
    } else {
      status = await commands.status();
    }
    await _mirror.update(status!, state?.intentRevision);
    await calls.flushActions();
    final more = await delivery.flush();
    if (more) _dirty = true;
    if (_subscription != null) failure = null;
    if (!_disposed) notifyListeners();
  }

  void _platformChanged() {
    // Both new platform facts and queued call actions require a turn. The
    // execution mirror deduplicates unchanged facts at its command boundary.
    _schedule();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    platform.removeListener(_platformChanged);
    calls.dispose();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
