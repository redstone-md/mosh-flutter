// Dispatch tests for `chat_actions.dart` -- the shared DM/channel/group
// send/retry/attachment/download/cancel/leave seam (Gap 4). Each test drives
// one dispatch helper against a recording fake Gateway and asserts the
// right Gateway method was called with the right named args for the given
// [ChatTarget] kind. `sameChatTarget` is covered too.
//
// The recording Gateway overrides each dispatch method explicitly to record
// its args and return a minimal real instance of its declared return type.
// The dispatch helpers' switches return the gateway Future verbatim, so the
// runtime subtype check on `Future<T>` requires the recording Future to be
// statically `Future<T>` (a `Future<dynamic>` from a `noSuchMethod` switch
// fails the implicit cast). Mirrors the per-method override idiom in the
// failed_retry suites' `_RecordingGateway extends FakeGateway`.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/shared/chat_actions.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;
import 'package:mosh/src/rust/channel_runtime.dart'
    show ChannelLeaveResult, ChannelSendResult;
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentSendResult, CloseSessionResult, SendMessageResult;
import 'package:mosh/src/rust/private_group_runtime.dart'
    show GroupLeaveResult, GroupSendResult;

/// A recording fake Gateway. Each dispatch method records its args into
/// [calls] and returns a minimal real instance of its declared return type
/// so the dispatch helpers' `Future<T>` subtype check passes. Non-dispatched
/// surface throws `UnimplementedError` via `noSuchMethod` so an unexpected
/// call surfaces loudly instead of silently no-opping.
class _RecordingGateway implements Gateway {
  final List<_Call> calls = [];

  void _record(String name, {Map<String, dynamic> named = const {}}) =>
      calls.add(_Call(name, named: named));

  @override
  Future<SendMessageResult> sendMessage(
      {required String sessionId, required String body}) {
    _record('sendMessage', named: {'sessionId': sessionId, 'body': body});
    return Future.value(_sendMsg);
  }

  @override
  Future<SendMessageResult> retryDmMessage(
      {required String sessionId, required String messageId}) {
    _record('retryDmMessage',
        named: {'sessionId': sessionId, 'messageId': messageId});
    return Future.value(_sendMsg);
  }

  @override
  Future<ChannelSendResult> sendChannel(
      {required String name, required String body}) {
    _record('sendChannel', named: {'name': name, 'body': body});
    return Future.value(_channelSend);
  }

  @override
  Future<ChannelSendResult> retryChannelMessage(
      {required String name, required String messageId}) {
    _record('retryChannelMessage',
        named: {'name': name, 'messageId': messageId});
    return Future.value(_channelSend);
  }

  @override
  Future<GroupSendResult> sendGroup(
      {required String groupId, required String body}) {
    _record('sendGroup', named: {'groupId': groupId, 'body': body});
    return Future.value(_groupSend);
  }

  @override
  Future<GroupSendResult> retryGroupMessage(
      {required String groupId, required String messageId}) {
    _record('retryGroupMessage',
        named: {'groupId': groupId, 'messageId': messageId});
    return Future.value(_groupSend);
  }

  @override
  Future<AttachmentSendResult> sendPrivateAttachment({
    required String sessionId,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) {
    _record('sendPrivateAttachment', named: {
      'sessionId': sessionId,
      'fileName': fileName,
      'mime': mime,
      'dataBase64': dataBase64,
      'thumbnailBase64': thumbnailBase64,
      'voice': voice,
    });
    return Future.value(_attSend);
  }

  @override
  Future<AttachmentSendResult> sendChannelAttachment({
    required String name,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) {
    _record('sendChannelAttachment', named: {
      'name': name,
      'fileName': fileName,
      'mime': mime,
      'dataBase64': dataBase64,
      'thumbnailBase64': thumbnailBase64,
      'voice': voice,
    });
    return Future.value(_attSend);
  }

  @override
  Future<AttachmentSendResult> sendGroupAttachment({
    required String groupId,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) {
    _record('sendGroupAttachment', named: {
      'groupId': groupId,
      'fileName': fileName,
      'mime': mime,
      'dataBase64': dataBase64,
      'thumbnailBase64': thumbnailBase64,
      'voice': voice,
    });
    return Future.value(_attSend);
  }

  @override
  Future<void> downloadAttachment(
      {required String sessionId, required String attachmentId}) {
    _record('downloadAttachment',
        named: {'sessionId': sessionId, 'attachmentId': attachmentId});
    return Future<void>.value();
  }

  @override
  Future<void> cancelAttachment(
      {required String sessionId, required String attachmentId}) {
    _record('cancelAttachment',
        named: {'sessionId': sessionId, 'attachmentId': attachmentId});
    return Future<void>.value();
  }

  @override
  Future<void> downloadChannelAttachment(
      {required String name, required String attachmentId}) {
    _record('downloadChannelAttachment',
        named: {'name': name, 'attachmentId': attachmentId});
    return Future<void>.value();
  }

  @override
  Future<void> cancelChannelAttachment(
      {required String name, required String attachmentId}) {
    _record('cancelChannelAttachment',
        named: {'name': name, 'attachmentId': attachmentId});
    return Future<void>.value();
  }

  @override
  Future<void> downloadGroupAttachment(
      {required String groupId, required String attachmentId}) {
    _record('downloadGroupAttachment',
        named: {'groupId': groupId, 'attachmentId': attachmentId});
    return Future<void>.value();
  }

  @override
  Future<void> cancelGroupAttachment(
      {required String groupId, required String attachmentId}) {
    _record('cancelGroupAttachment',
        named: {'groupId': groupId, 'attachmentId': attachmentId});
    return Future<void>.value();
  }

  @override
  Future<CloseSessionResult> closeSession({required String sessionId}) {
    _record('closeSession', named: {'sessionId': sessionId});
    return Future.value(const CloseSessionResult(sessionId: '', closed: true));
  }

  @override
  Future<ChannelLeaveResult> leaveChannel({required String name}) {
    _record('leaveChannel', named: {'name': name});
    return Future.value(const ChannelLeaveResult(name: '', closed: true));
  }

  @override
  Future<GroupLeaveResult> closeGroup({required String groupId}) {
    _record('closeGroup', named: {'groupId': groupId});
    return Future.value(const GroupLeaveResult(groupId: '', closed: true));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(' ${invocation.memberName}');
}

/// Minimal real `SendMessageResult` sentinel. Top-level `final` (not `const`)
/// because `BigInt.zero` is not usable as a const expression in these
/// frb-generated constructors; the dispatch helpers only need a runtime
/// instance of the right type.
final SendMessageResult _sendMsg = SendMessageResult(
  sessionId: '',
  state: '',
  ciphertextBytes: BigInt.zero,
  messageId: '',
  sentAtMs: BigInt.zero,
  deliveryStatus: MessageDeliveryStatus.pending,
);

final ChannelSendResult _channelSend = ChannelSendResult(
  name: '',
  bytes: BigInt.zero,
  messageId: '',
  sentAtMs: BigInt.zero,
  deliveryStatus: MessageDeliveryStatus.pending,
);

final GroupSendResult _groupSend = GroupSendResult(
  groupId: '',
  bytes: BigInt.zero,
  messageId: '',
  sentAtMs: BigInt.zero,
  deliveryStatus: MessageDeliveryStatus.pending,
);

final AttachmentSendResult _attSend =
    AttachmentSendResult(sessionId: '', attachmentId: 'a', contentHash: 'h');

class _Call {
  const _Call(this.name, {this.named = const {}});

  final String name;
  final Map<String, dynamic> named;

  @override
  String toString() =>
      '$name(${named.entries.map((e) => '${e.key}=${e.value}').join(', ')})';
}

void main() {
  late _RecordingGateway gateway;

  setUp(() => gateway = _RecordingGateway());

  group('sendChatText', () {
    test('DmTarget -> sendMessage(sessionId, body)', () async {
      await sendChatText(
        gateway: gateway,
        target: DmTarget('s1'),
        body: 'hi',
      );
      final call = gateway.calls.single;
      expect(call.name, 'sendMessage');
      expect(call.named['sessionId'], 's1');
      expect(call.named['body'], 'hi');
    });

    test('ChannelTarget -> sendChannel(name, body)', () async {
      await sendChatText(
        gateway: gateway,
        target: ChannelTarget('#room'),
        body: 'yo',
      );
      final call = gateway.calls.single;
      expect(call.name, 'sendChannel');
      expect(call.named['name'], '#room');
      expect(call.named['body'], 'yo');
    });

    test('GroupTarget -> sendGroup(groupId, body)', () async {
      await sendChatText(
        gateway: gateway,
        target: GroupTarget('g1'),
        body: 'gm',
      );
      final call = gateway.calls.single;
      expect(call.name, 'sendGroup');
      expect(call.named['groupId'], 'g1');
      expect(call.named['body'], 'gm');
    });
  });

  group('retryChatMessage', () {
    test('DmTarget -> retryDmMessage(sessionId, messageId)', () async {
      await retryChatMessage(
        gateway: gateway,
        target: DmTarget('s1'),
        messageId: 'm1',
      );
      final call = gateway.calls.single;
      expect(call.name, 'retryDmMessage');
      expect(call.named['sessionId'], 's1');
      expect(call.named['messageId'], 'm1');
    });

    test('ChannelTarget -> retryChannelMessage(name, messageId)', () async {
      await retryChatMessage(
        gateway: gateway,
        target: ChannelTarget('#room'),
        messageId: 'm2',
      );
      final call = gateway.calls.single;
      expect(call.name, 'retryChannelMessage');
      expect(call.named['name'], '#room');
      expect(call.named['messageId'], 'm2');
    });

    test('GroupTarget -> retryGroupMessage(groupId, messageId)', () async {
      await retryChatMessage(
        gateway: gateway,
        target: GroupTarget('g1'),
        messageId: 'm3',
      );
      final call = gateway.calls.single;
      expect(call.name, 'retryGroupMessage');
      expect(call.named['groupId'], 'g1');
      expect(call.named['messageId'], 'm3');
    });
  });

  group('sendChatAttachment', () {
    test('DmTarget -> sendPrivateAttachment(sessionId, fileName, mime, ...)',
        () async {
      await sendChatAttachment(
        gateway: gateway,
        target: DmTarget('s1'),
        fileName: 'a.txt',
        mime: 'text/plain',
        dataBase64: 'AAA',
        thumbnailBase64: 'T',
      );
      final call = gateway.calls.single;
      expect(call.name, 'sendPrivateAttachment');
      expect(call.named['sessionId'], 's1');
      expect(call.named['fileName'], 'a.txt');
      expect(call.named['mime'], 'text/plain');
      expect(call.named['dataBase64'], 'AAA');
      expect(call.named['thumbnailBase64'], 'T');
      expect(call.named['voice'], isNull);
    });

    test('ChannelTarget -> sendChannelAttachment(name, fileName, ...)',
        () async {
      await sendChatAttachment(
        gateway: gateway,
        target: ChannelTarget('#room'),
        fileName: 'a.png',
        mime: 'image/png',
        dataBase64: 'BBB',
      );
      final call = gateway.calls.single;
      expect(call.name, 'sendChannelAttachment');
      expect(call.named['name'], '#room');
      expect(call.named['fileName'], 'a.png');
      expect(call.named['dataBase64'], 'BBB');
    });

    test('GroupTarget -> sendGroupAttachment(groupId, fileName, ...)',
        () async {
      await sendChatAttachment(
        gateway: gateway,
        target: GroupTarget('g1'),
        fileName: 'a.mp3',
        mime: 'audio/mp4',
        dataBase64: 'CCC',
      );
      final call = gateway.calls.single;
      expect(call.name, 'sendGroupAttachment');
      expect(call.named['groupId'], 'g1');
      expect(call.named['fileName'], 'a.mp3');
    });
  });

  group('downloadChatAttachment', () {
    test('DmTarget -> downloadAttachment(sessionId, attachmentId)', () async {
      await downloadChatAttachment(
        gateway: gateway,
        target: DmTarget('s1'),
        attachmentId: 'att1',
      );
      final call = gateway.calls.single;
      expect(call.name, 'downloadAttachment');
      expect(call.named['sessionId'], 's1');
      expect(call.named['attachmentId'], 'att1');
    });

    test('ChannelTarget -> downloadChannelAttachment(name, attachmentId)',
        () async {
      await downloadChatAttachment(
        gateway: gateway,
        target: ChannelTarget('#room'),
        attachmentId: 'att2',
      );
      final call = gateway.calls.single;
      expect(call.name, 'downloadChannelAttachment');
      expect(call.named['name'], '#room');
      expect(call.named['attachmentId'], 'att2');
    });

    test('GroupTarget -> downloadGroupAttachment(groupId, attachmentId)',
        () async {
      await downloadChatAttachment(
        gateway: gateway,
        target: GroupTarget('g1'),
        attachmentId: 'att3',
      );
      final call = gateway.calls.single;
      expect(call.name, 'downloadGroupAttachment');
      expect(call.named['groupId'], 'g1');
      expect(call.named['attachmentId'], 'att3');
    });
  });

  group('cancelChatAttachment', () {
    test('DmTarget -> cancelAttachment(sessionId, attachmentId)', () async {
      await cancelChatAttachment(
        gateway: gateway,
        target: DmTarget('s1'),
        attachmentId: 'att1',
      );
      final call = gateway.calls.single;
      expect(call.name, 'cancelAttachment');
      expect(call.named['sessionId'], 's1');
      expect(call.named['attachmentId'], 'att1');
    });

    test('ChannelTarget -> cancelChannelAttachment(name, attachmentId)',
        () async {
      await cancelChatAttachment(
        gateway: gateway,
        target: ChannelTarget('#room'),
        attachmentId: 'att2',
      );
      final call = gateway.calls.single;
      expect(call.name, 'cancelChannelAttachment');
      expect(call.named['name'], '#room');
      expect(call.named['attachmentId'], 'att2');
    });

    test('GroupTarget -> cancelGroupAttachment(groupId, attachmentId)',
        () async {
      await cancelChatAttachment(
        gateway: gateway,
        target: GroupTarget('g1'),
        attachmentId: 'att3',
      );
      final call = gateway.calls.single;
      expect(call.name, 'cancelGroupAttachment');
      expect(call.named['groupId'], 'g1');
      expect(call.named['attachmentId'], 'att3');
    });
  });

  group('closeChatTarget', () {
    test('DmTarget -> closeSession(sessionId)', () async {
      await closeChatTarget(gateway: gateway, target: DmTarget('s1'));
      final call = gateway.calls.single;
      expect(call.name, 'closeSession');
      expect(call.named['sessionId'], 's1');
    });

    test('ChannelTarget -> leaveChannel(name)', () async {
      await closeChatTarget(gateway: gateway, target: ChannelTarget('#room'));
      final call = gateway.calls.single;
      expect(call.name, 'leaveChannel');
      expect(call.named['name'], '#room');
    });

    test('GroupTarget -> closeGroup(groupId)', () async {
      await closeChatTarget(gateway: gateway, target: GroupTarget('g1'));
      final call = gateway.calls.single;
      expect(call.name, 'closeGroup');
      expect(call.named['groupId'], 'g1');
    });
  });

  group('sameChatTarget', () {
    test('same kind + same id -> true', () {
      expect(sameChatTarget(DmTarget('s1'), DmTarget('s1')), isTrue);
      expect(sameChatTarget(ChannelTarget('#r'), ChannelTarget('#r')), isTrue);
      expect(sameChatTarget(GroupTarget('g1'), GroupTarget('g1')), isTrue);
    });

    test('different kind -> false (even with shared id)', () {
      expect(sameChatTarget(DmTarget('x'), ChannelTarget('x')), isFalse);
      expect(sameChatTarget(DmTarget('x'), GroupTarget('x')), isFalse);
      expect(sameChatTarget(ChannelTarget('x'), GroupTarget('x')), isFalse);
    });

    test('same kind + different id -> false', () {
      expect(sameChatTarget(DmTarget('a'), DmTarget('b')), isFalse);
      expect(sameChatTarget(ChannelTarget('a'), ChannelTarget('b')), isFalse);
      expect(sameChatTarget(GroupTarget('a'), GroupTarget('b')), isFalse);
    });
  });
}
