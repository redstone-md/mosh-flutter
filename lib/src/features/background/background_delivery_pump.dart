import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'background_commands.dart';

/// Replays durable revisions with the same OS identity; refusal is never acked.
class BackgroundDeliveryPump {
  BackgroundDeliveryPump(this.commands, this.platform);
  final BackgroundCommands commands;
  final AndroidWaitingPlatform platform;

  /// Bounded batches yield to foreground work. True requests another turn.
  Future<bool> flush() async {
    for (var batch = 0; batch < 4; batch++) {
      final entries = await commands.pending();
      var refused = false;
      for (final entry in entries) {
        final result = await platform.publishNotification(
          id: entry.id,
          revision: entry.revision.toInt(),
          messageCount: entry.messageCount,
          sender: entry.sender,
          text: entry.text,
        );
        if (result == 'posted') {
          await commands.acknowledge(entry);
        } else {
          refused = true;
        }
      }
      if (refused || entries.length < 16) return false;
      await Future<void>.delayed(Duration.zero);
    }
    return true;
  }
}
