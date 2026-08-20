// Dispatch tests for `chat_actions.dart` -- the shared DM/channel/group
// send/retry/attachment/download/cancel/leave seam (Gap 4). Each test drives
// one dispatch helper against the scriptable test gateway and asserts the
// right Gateway method was called with the right named args for the given
// [ChatTarget] kind. `sameChatTarget` is covered too.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/shared/chat_actions.dart';

import '../../support/scriptable_gateway.dart';

void main() {
  late ScriptableGateway gateway;

  setUp(() => gateway = ScriptableGateway());

  group('sendChatText', () {
    test('DmTarget -> sendMessage(sessionId, body)', () async {
      await sendChatText(
        gateway: gateway,
        target: DmTarget('s1'),
        body: 'hi',
      );
      final call = gateway.calls.single;
      expect(call.method, GatewayMethod.sendMessage);
      expect(call.args['sessionId'], 's1');
      expect(call.args['body'], 'hi');
    });

    test('ChannelTarget -> sendChannel(name, body)', () async {
      await sendChatText(
        gateway: gateway,
        target: ChannelTarget('#room'),
        body: 'yo',
      );
      final call = gateway.calls.single;
      expect(call.method, GatewayMethod.sendChannel);
      expect(call.args['name'], '#room');
      expect(call.args['body'], 'yo');
    });

    test('GroupTarget -> sendGroup(groupId, body)', () async {
      await sendChatText(
        gateway: gateway,
        target: GroupTarget('g1'),
        body: 'gm',
      );
      final call = gateway.calls.single;
      expect(call.method, GatewayMethod.sendGroup);
      expect(call.args['groupId'], 'g1');
      expect(call.args['body'], 'gm');
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
      expect(call.method, GatewayMethod.retryDmMessage);
      expect(call.args['sessionId'], 's1');
      expect(call.args['messageId'], 'm1');
    });

    test('ChannelTarget -> retryChannelMessage(name, messageId)', () async {
      await retryChatMessage(
        gateway: gateway,
        target: ChannelTarget('#room'),
        messageId: 'm2',
      );
      final call = gateway.calls.single;
      expect(call.method, GatewayMethod.retryChannelMessage);
      expect(call.args['name'], '#room');
      expect(call.args['messageId'], 'm2');
    });

    test('GroupTarget -> retryGroupMessage(groupId, messageId)', () async {
      await retryChatMessage(
        gateway: gateway,
        target: GroupTarget('g1'),
        messageId: 'm3',
      );
      final call = gateway.calls.single;
      expect(call.method, GatewayMethod.retryGroupMessage);
      expect(call.args['groupId'], 'g1');
      expect(call.args['messageId'], 'm3');
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
      expect(call.method, GatewayMethod.sendPrivateAttachment);
      expect(call.args['sessionId'], 's1');
      expect(call.args['fileName'], 'a.txt');
      expect(call.args['mime'], 'text/plain');
      expect(call.args['dataBase64'], 'AAA');
      expect(call.args['thumbnailBase64'], 'T');
      expect(call.args['voice'], isNull);
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
      expect(call.method, GatewayMethod.sendChannelAttachment);
      expect(call.args['name'], '#room');
      expect(call.args['fileName'], 'a.png');
      expect(call.args['dataBase64'], 'BBB');
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
      expect(call.method, GatewayMethod.sendGroupAttachment);
      expect(call.args['groupId'], 'g1');
      expect(call.args['fileName'], 'a.mp3');
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
      expect(call.method, GatewayMethod.downloadAttachment);
      expect(call.args['sessionId'], 's1');
      expect(call.args['attachmentId'], 'att1');
    });

    test('ChannelTarget -> downloadChannelAttachment(name, attachmentId)',
        () async {
      await downloadChatAttachment(
        gateway: gateway,
        target: ChannelTarget('#room'),
        attachmentId: 'att2',
      );
      final call = gateway.calls.single;
      expect(call.method, GatewayMethod.downloadChannelAttachment);
      expect(call.args['name'], '#room');
      expect(call.args['attachmentId'], 'att2');
    });

    test('GroupTarget -> downloadGroupAttachment(groupId, attachmentId)',
        () async {
      await downloadChatAttachment(
        gateway: gateway,
        target: GroupTarget('g1'),
        attachmentId: 'att3',
      );
      final call = gateway.calls.single;
      expect(call.method, GatewayMethod.downloadGroupAttachment);
      expect(call.args['groupId'], 'g1');
      expect(call.args['attachmentId'], 'att3');
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
      expect(call.method, GatewayMethod.cancelAttachment);
      expect(call.args['sessionId'], 's1');
      expect(call.args['attachmentId'], 'att1');
    });

    test('ChannelTarget -> cancelChannelAttachment(name, attachmentId)',
        () async {
      await cancelChatAttachment(
        gateway: gateway,
        target: ChannelTarget('#room'),
        attachmentId: 'att2',
      );
      final call = gateway.calls.single;
      expect(call.method, GatewayMethod.cancelChannelAttachment);
      expect(call.args['name'], '#room');
      expect(call.args['attachmentId'], 'att2');
    });

    test('GroupTarget -> cancelGroupAttachment(groupId, attachmentId)',
        () async {
      await cancelChatAttachment(
        gateway: gateway,
        target: GroupTarget('g1'),
        attachmentId: 'att3',
      );
      final call = gateway.calls.single;
      expect(call.method, GatewayMethod.cancelGroupAttachment);
      expect(call.args['groupId'], 'g1');
      expect(call.args['attachmentId'], 'att3');
    });
  });

  group('closeChatTarget', () {
    test('DmTarget -> closeSession(sessionId)', () async {
      await closeChatTarget(gateway: gateway, target: DmTarget('s1'));
      final call = gateway.calls.single;
      expect(call.method, GatewayMethod.closeSession);
      expect(call.args['sessionId'], 's1');
    });

    test('ChannelTarget -> leaveChannel(name)', () async {
      await closeChatTarget(gateway: gateway, target: ChannelTarget('#room'));
      final call = gateway.calls.single;
      expect(call.method, GatewayMethod.leaveChannel);
      expect(call.args['name'], '#room');
    });

    test('GroupTarget -> closeGroup(groupId)', () async {
      await closeChatTarget(gateway: gateway, target: GroupTarget('g1'));
      final call = gateway.calls.single;
      expect(call.method, GatewayMethod.closeGroup);
      expect(call.args['groupId'], 'g1');
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
