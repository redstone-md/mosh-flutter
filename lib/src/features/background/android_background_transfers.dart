import 'package:mosh/src/gateway/attachment_execution.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:mosh/src/rust/api/background/types.dart';
import 'package:mosh/src/rust/api/conversation.dart';
import 'package:mosh/src/rust/persistence/user_transfers/types.dart';
import 'background_commands.dart';

/// The installation owner coordinates gestures and durable OS actions; only JNI
/// callbacks from actual OS execution can grant background byte movement.
class AndroidBackgroundTransfers implements AttachmentExecution {
  AndroidBackgroundTransfers(this.commands, this.platform);
  final BackgroundCommands commands;
  final AndroidWaitingPlatform platform;
  final Map<String, DateTime> _deferredAttempts = {};

  @override
  Future<void> send(
      BridgeConversationRef target, BridgeAttachmentPayload payload) async {
    final encoded = payload.dataBase64;
    final padding = encoded.endsWith('==')
        ? 2
        : encoded.endsWith('=')
            ? 1
            : 0;
    final admission = await commands.prepareTransfer(
        target,
        UserTransferDirection.upload,
        null,
        BigInt.from(encoded.length ~/ 4 * 3 - padding));
    await _begin(admission);
    await commands.sendTransfer(admission.id, payload);
  }

  @override
  Future<void> download(
      BridgeConversationRef target, String attachmentId) async {
    final admission = await commands.prepareTransfer(
        target, UserTransferDirection.download, attachmentId, BigInt.zero);
    await _begin(admission);
    await commands.downloadTransfer(admission.id);
  }

  Future<void> _begin(UserTransfer admission) async {
    // A refusal does not cancel a visible operation. Native code pauses it on
    // leaving the Activity if no actual OS execution callback was granted.
    await platform.beginTransfer(
        admission.id, admission.direction.name, admission.totalBytes);
  }

  Future<void> flushActions() async {
    for (final action in await platform.takeTransferActions()) {
      if (action.action == 'cancel') {
        await commands.cancelTransfer(action.id);
      } else {
        if (platform.state?.interactive != true) continue;
        await commands.resumeTransfer(action.id);
        final status = await commands.status();
        final record = status.userTransfers
            .where((value) => value.id == action.id)
            .firstOrNull;
        if (record != null) await _begin(record);
      }
      await platform.acknowledgeTransferActions([action]);
    }
  }

  Future<void> scheduleDeferred(BackgroundStatus status) async {
    final now = DateTime.now();
    final ids = status.userTransfers.map((value) => value.id).toSet();
    _deferredAttempts.removeWhere((id, _) => !ids.contains(id));
    for (final transfer in status.userTransfers) {
      if (transfer.direction != UserTransferDirection.upload ||
          transfer.state != UserTransferState.waitingExecution) {
        continue;
      }
      final previous = _deferredAttempts[transfer.id];
      if (previous != null &&
          now.difference(previous) < const Duration(minutes: 3)) {
        continue;
      }
      _deferredAttempts[transfer.id] = now;
      await platform.beginTransfer(
          transfer.id, transfer.direction.name, transfer.totalBytes,
          deferred: true);
    }
  }
}
