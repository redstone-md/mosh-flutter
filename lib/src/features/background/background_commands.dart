import 'package:mosh/src/rust/api/background.dart' as api;
import 'package:mosh/src/rust/api/background/types.dart';
import 'package:mosh/src/rust/api/background/call_actions.dart';
import 'package:mosh/src/rust/api/private_dm.dart' as dm;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/persistence/background_delivery.dart';

/// The approved installation bridge; widgets never own native background work.
class BackgroundCommands {
  Future<BackgroundStatus> setExecution({
    required bool interactive,
    required bool waitingEnabled,
  }) =>
      api.setBackgroundExecution(
          interactive: interactive, waitingEnabled: waitingEnabled);

  Future<BackgroundStatus> status() => api.backgroundStatus();
  Future<SessionSnapshot> callSnapshot(String id) =>
      dm.pollSession(sessionId: id);
  Future<BackgroundCallActionResult> callAction(String capability) =>
      api.applyBackgroundCallAction(capability: capability);
  Stream<BigInt> changes() => api.watchBackgroundChanges();
  Future<List<BackgroundNotification>> pending() =>
      api.pendingBackgroundNotifications(limit: 16);
  Future<void> acknowledge(BackgroundNotification entry) =>
      api.ackBackgroundNotification(id: entry.id, revision: entry.revision);
}
