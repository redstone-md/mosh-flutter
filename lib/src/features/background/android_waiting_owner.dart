import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:mosh/src/rust/api/background/types.dart';
import 'background_commands.dart';
import 'background_delivery_pump.dart';

final androidWaitingOwnerProvider =
    Provider<AndroidWaitingOwner?>((ref) => null);

/// Process-owned execution and notification intake, independent of mounted chats.
class AndroidWaitingOwner extends ChangeNotifier {
  AndroidWaitingOwner(this.platform, this.commands)
      : delivery = BackgroundDeliveryPump(commands, platform) {
    platform.addListener(_platformChanged);
  }
  final AndroidWaitingPlatform platform;
  final BackgroundCommands commands;
  final BackgroundDeliveryPump delivery;
  BackgroundStatus? status;
  Object? failure;
  bool _keyReady = false, _setupReady = false, _attached = false;
  bool _disposed = false, _dirty = false;
  Future<void>? _work;
  StreamSubscription<BigInt>? _subscription;
  Object? _observedPlatform, _appliedExecution, _appliedWork;
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
    await _mirrorWork(status!, state?.intentRevision);
    final more = await delivery.flush();
    if (more) _dirty = true;
    if (_subscription != null) failure = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> _mirrorWork(
      BackgroundStatus current, int? intentRevision) async {
    final facts = (
      intentRevision,
      current.requestedMode,
      current.actualMode,
      current.reachability,
      current.attachmentCount,
      current.currentCalls,
      current.currentUserTransfers,
      current.limitation
    );
    if (facts != _appliedWork) {
      await platform.setUserWork({
        'intentRevision': intentRevision,
        'requestedMode': current.requestedMode.name,
        'actualMode': current.actualMode.name,
        'reachability': current.reachability.name,
        'attachmentCount': current.attachmentCount,
        'currentCalls': current.currentCalls,
        'currentUserTransfers': current.currentUserTransfers,
        'limitation': current.limitation,
      });
      _appliedWork = facts;
    }
  }

  void _platformChanged() {
    final state = platform.state;
    final facts = state == null
        ? null
        : (
            state.intentRevision,
            state.interactive,
            state.waitingEnabled,
            state.serviceRunning,
            state.setupComplete,
            state.notificationsAllowed,
            state.batteryExempt,
            state.showNamesWhenLocked,
            state.showTextWhenLocked
          );
    if (facts != _observedPlatform) {
      _observedPlatform = facts;
      _schedule();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    platform.removeListener(_platformChanged);
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
