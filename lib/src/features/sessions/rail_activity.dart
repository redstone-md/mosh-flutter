import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/message_deletion/types.dart';

/// A single pass over history supplies the list preview and searchable names.
/// Control events without text or an attachment never change recent-chat order.
class RailActivity {
  const RailActivity({
    this.text,
    this.deletion,
    this.sender,
    this.own = false,
    this.sentAtMs,
    this.participantNames = '',
  });

  final String? text;
  final DeletionMarker? deletion;
  final String? sender;
  final bool own;
  final BigInt? sentAtMs;
  final String participantNames;

  factory RailActivity.dm(SessionSnapshot snapshot) => _read(
        snapshot.messages,
        content: (m) => _content(m.body, m.attachment?.fileName),
        deletion: (m) => m.metadata?.deletion,
        time: (m) => m.sentAtMs,
        sender: (m) => m.fromDevice,
        own: (m) => m.fromDevice == snapshot.displayName,
      );

  factory RailActivity.channel(ChannelSnapshot snapshot) => _read(
        snapshot.messages,
        content: (m) => _content(m.body, m.attachment?.fileName),
        deletion: (m) => m.metadata?.deletion,
        time: (m) => m.sentAtMs,
        sender: (m) => m.fromDevice,
        own: (m) => m.fromFingerprint == snapshot.deviceFingerprint,
      );

  factory RailActivity.group(GroupSnapshot snapshot) => _read(
        snapshot.messages,
        content: (m) => _content(m.body, m.attachment?.fileName),
        deletion: (m) => m.metadata?.deletion,
        time: (m) => m.sentAtMs,
        sender: (m) => m.fromDevice,
        own: (m) => m.fromFingerprint == snapshot.deviceFingerprint,
      );
}

String? _content(String body, String? fileName) => body.trim().isNotEmpty
    ? body.replaceAll(RegExp(r'\s+'), ' ').trim()
    : fileName;

RailActivity _read<T>(
  List<T> messages, {
  required String? Function(T) content,
  required DeletionMarker? Function(T) deletion,
  required BigInt? Function(T) time,
  required String Function(T) sender,
  required bool Function(T) own,
}) {
  T? latest;
  BigInt? latestTime;
  final names = <String>{};
  for (final message in messages) {
    names.add(sender(message));
    if (content(message) == null && deletion(message) == null) continue;
    final at = time(message);
    if (latest != null &&
        latestTime != null &&
        (at == null || at < latestTime)) {
      continue;
    }
    latest = message;
    latestTime = at;
  }
  return RailActivity(
    text: latest == null ? null : content(latest),
    deletion: latest == null ? null : deletion(latest),
    sender: latest == null ? null : sender(latest),
    own: latest != null && own(latest),
    sentAtMs: latestTime,
    participantNames: names.join(' '),
  );
}
