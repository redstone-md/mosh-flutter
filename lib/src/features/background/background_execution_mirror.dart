import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:mosh/src/rust/persistence/user_transfers/types.dart';
import 'package:mosh/src/rust/api/background/types.dart';

/// Only verified native work facts can retain a service after Stop waiting.
class BackgroundExecutionMirror {
  BackgroundExecutionMirror(this.platform);
  final AndroidWaitingPlatform platform;
  Object? _appliedWork;
  List<UserTransfer>? _appliedTransfers;

  Future<void> update(BackgroundStatus current, int? intentRevision) async {
    final facts = (
      intentRevision,
      current.requestedMode,
      current.actualMode,
      current.reachability,
      current.attachmentCount,
      current.currentCalls,
      current.currentUserTransfers,
      current.limitation,
    );
    if (facts != _appliedWork ||
        !listEquals(current.userTransfers, _appliedTransfers)) {
      await platform.setUserWork({
        'intentRevision': intentRevision,
        'requestedMode': current.requestedMode.name,
        'actualMode': current.actualMode.name,
        'reachability': current.reachability.name,
        'attachmentCount': current.attachmentCount,
        'currentCalls': current.currentCalls,
        'currentUserTransfers': current.currentUserTransfers,
        'limitation': current.limitation,
        'transfers': [
          for (final transfer in current.userTransfers)
            {
              'id': transfer.id,
              'direction': transfer.direction.name,
              'state': transfer.state.name,
              'completedBytes': transfer.completedBytes.toInt(),
              'totalBytes': transfer.totalBytes.toInt(),
            }
        ],
      });
      _appliedWork = facts;
      _appliedTransfers = current.userTransfers;
    }
  }
}
