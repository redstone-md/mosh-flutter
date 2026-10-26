import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:mosh/src/rust/api/background/types.dart';

/// Only verified native work facts can retain a service after Stop waiting.
class BackgroundExecutionMirror {
  BackgroundExecutionMirror(this.platform);
  final AndroidWaitingPlatform platform;
  Object? _appliedWork;

  Future<void> update(BackgroundStatus current, int? intentRevision) async {
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
}
