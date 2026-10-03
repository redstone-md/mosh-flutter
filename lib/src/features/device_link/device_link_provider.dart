import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/platform/foreground_poller.dart';
import 'package:mosh/src/rust/device_link/types.dart';

import 'device_link_commands.dart';
import 'device_link_state.dart';

final deviceLinkCommandsProvider =
    Provider<DeviceLinkCommands>((ref) => DeviceLinkCommands());

/// Tests drive refresh explicitly while retaining the real workflow.
final deviceLinkPollIntervalProvider =
    Provider<Duration?>((ref) => const Duration(seconds: 1));

final deviceLinkProvider =
    AsyncNotifierProvider.autoDispose<DeviceLinkController, DeviceLinkState>(
  DeviceLinkController.new,
);

class DeviceLinkController extends AsyncNotifier<DeviceLinkState> {
  bool _reading = false;
  int _actionRevision = 0;

  @override
  Future<DeviceLinkState> build() async {
    _reading = false;
    _actionRevision++;
    final commands = ref.watch(deviceLinkCommandsProvider);
    final interval = ref.watch(deviceLinkPollIntervalProvider);
    if (interval != null) {
      final poller = ForegroundPoller(interval, refresh);
      ref.onDispose(poller.dispose);
    }
    return DeviceLinkState(snapshot: await commands.snapshot());
  }

  Future<void> refresh() async {
    if (_reading || state.isLoading || state.value?.busy == true) return;
    _reading = true;
    final startedUnder = ref;
    final revision = _actionRevision;
    try {
      final value =
          await startedUnder.read(deviceLinkCommandsProvider).snapshot();
      if (startedUnder.mounted && revision == _actionRevision) {
        state = AsyncData(DeviceLinkState(
            snapshot: value, actionError: state.value?.actionError));
      }
    } catch (error, stack) {
      if (startedUnder.mounted && revision == _actionRevision) {
        final previous = state.value;
        state = previous == null
            ? AsyncError(error, stack)
            : AsyncData(previous.copyWith(readError: error));
      }
    } finally {
      if (startedUnder.mounted) _reading = false;
    }
  }

  Future<T> _exclusive<T>(
      Future<T> Function(Ref, DeviceLinkCommands) action) async {
    final current = state.value;
    if (current == null || current.busy) {
      throw const DeviceLinkError(
          kind: DeviceLinkErrorKind.busy,
          message: 'A device-link action is already pending');
    }
    _actionRevision++;
    final startedUnder = ref;
    final commands = startedUnder.read(deviceLinkCommandsProvider);
    state = AsyncData(current.copyWith(busy: true, clearError: true));
    try {
      return await action(startedUnder, commands);
    } finally {
      if (startedUnder.mounted) {
        _actionRevision++;
        state = AsyncData(state.requireValue.copyWith(busy: false));
      }
    }
  }

  Future<T> _recordFailure<T>(
      Ref startedUnder, Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      if (startedUnder.mounted) {
        state = AsyncData(state.requireValue.copyWith(actionError: error));
      }
      rethrow;
    }
  }

  Future<DeviceLinkSnapshot> _update(
      Ref startedUnder, Future<DeviceLinkSnapshot> Function() action) async {
    final value = await _recordFailure(startedUnder, action);
    if (startedUnder.mounted) {
      state = AsyncData(
          state.requireValue.copyWith(snapshot: value, clearReadError: true));
    }
    return value;
  }

  Future<void> _act(
          Future<DeviceLinkSnapshot> Function(DeviceLinkCommands) action) =>
      _exclusive((startedUnder, commands) async {
        await _update(startedUnder, () => action(commands));
      });

  Future<void> beginLink() => _act((commands) => commands.beginLink());
  Future<void> joinLink(String uri, String name) =>
      _act((commands) => commands.joinLink(uri.trim(), name));
  Future<void> approve(String code) =>
      _act((commands) => commands.approve(code));
  Future<void> revoke(String deviceId) =>
      _act((commands) => commands.revoke(deviceId));

  /// Acquisition belongs to the same operation as join, including dismissal.
  Future<bool> joinFrom(Future<String?> Function() acquire, String name) =>
      _exclusive((startedUnder, commands) async {
        final uri = await _recordFailure(startedUnder, acquire);
        if (uri == null || !startedUnder.mounted) return false;
        await _update(startedUnder, () => commands.joinLink(uri.trim(), name));
        return startedUnder.mounted;
      });

  Future<DeviceLinkExit> cancel() => _exclusive((startedUnder, commands) async {
        final before = await _update(startedUnder, commands.snapshot);
        if (!startedUnder.mounted ||
            before.phase == DeviceLinkPhase.delivering) {
          return DeviceLinkExit.blocked;
        }
        return _cancel(startedUnder, commands, before);
      });

  /// Hold the action lock until setup progress is saved, without storing its error.
  Future<DeviceLinkExit> continueSetup(Future<void> Function() advance) =>
      _exclusive((startedUnder, commands) async {
        final before = await _update(startedUnder, commands.snapshot);
        if (!startedUnder.mounted ||
            before.phase == DeviceLinkPhase.delivering) {
          return DeviceLinkExit.blocked;
        }
        final outcome =
            before.role == null || before.phase == DeviceLinkPhase.linked
                ? DeviceLinkExit.ready
                : await _cancel(startedUnder, commands, before);
        if (outcome == DeviceLinkExit.ready && startedUnder.mounted) {
          await advance();
        }
        return outcome;
      });

  Future<bool> backSetup(Future<void> Function() navigate) =>
      _exclusive((startedUnder, commands) async {
        final current = await _update(startedUnder, commands.snapshot);
        if (!startedUnder.mounted ||
            DeviceLinkState(snapshot: current).pending ||
            current.phase == DeviceLinkPhase.delivering) {
          return false;
        }
        await navigate();
        return true;
      });

  Future<DeviceLinkExit> _cancel(Ref startedUnder, DeviceLinkCommands commands,
      DeviceLinkSnapshot before) async {
    final after = await _update(startedUnder, commands.cancel);
    if (!startedUnder.mounted ||
        after.phase == DeviceLinkPhase.delivering ||
        after.role != null && after.phase != DeviceLinkPhase.linked) {
      return DeviceLinkExit.blocked;
    }
    if (after.devices.length > before.devices.length ||
        before.canJoin && !after.canJoin) {
      return DeviceLinkExit.linkApproved;
    }
    return DeviceLinkExit.ready;
  }
}
