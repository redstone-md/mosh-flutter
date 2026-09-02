// Unit test for the conversation-seam test double itself: the message
// append, the teardown, and the recorded-call contract of the scripted
// methods. The bridge facade's double has its own self-test in
// scriptable_bridge_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

import 'gateway_snapshots.dart';
import 'scriptable_gateway.dart';

void main() {
  test('the test gateway send -> poll -> leave round trip', () async {
    final gateway = ScriptableGateway();
    gateway.seedSessions([
      fakeSession(
        sessionId: 'fake-session-1',
        displayName: 'alice',
        role: 'inviter',
        inviteUri: 'mosh://invite?session=fake-session-1#fp=FP',
        fingerprint: 'FP',
      ),
    ]);

    final target = DmTarget('fake-session-1');
    final before = (await gateway.poll(target)).messages.length;
    await gateway.send(target, body: 'hi');
    final appended = await gateway.poll(target);
    expect(appended.messages.length, before + 1);
    expect(appended.messages.last.body, 'hi');

    await gateway.leave(target);
    expect(gateway.conversations.sessions, isNot(contains('fake-session-1')));
  });

  // Attachment SEND seam: the double has no result to return (ADR 0024 drops
  // the success payload), so its contract is the recorded call -- a test
  // asserts what the screen asked for, and the new row shows up in whatever
  // the test seeds the next poll with.
  test('the test gateway DM sendAttachment records the call', () async {
    final gateway = ScriptableGateway();
    await gateway.sendAttachment(
      const DmTarget('fake-session-1'),
      fileName: 'photo.png',
      mime: 'image/png',
      dataBase64: 'iVBORw0KGgo=',
      thumbnailBase64: 'thumb',
    );
    final call = gateway.lastCall(GatewayMethod.sendAttachment);
    expect(call, isNotNull);
    expect(call!.target, const DmTarget('fake-session-1'));
    expect(call.arg<String>('fileName'), 'photo.png');
    expect(call.arg<String>('mime'), 'image/png');
    expect(call.arg<String>('dataBase64'), 'iVBORw0KGgo=');
    expect(call.arg<String>('thumbnailBase64'), 'thumb');
  });

  test('the test gateway dismissDmOffer records the offer host', () async {
    final gateway = ScriptableGateway();
    await gateway.dismissDmOffer(
      const ChannelTarget('drift-room'),
      offerId: 'offer-1',
    );
    final call = gateway.lastCall(GatewayMethod.dismissDmOffer);
    expect(call!.target, const ChannelTarget('drift-room'));
    expect(call.arg<String>('offerId'), 'offer-1');
  });

  test('an unseeded channel poll falls back to the canned snapshot', () async {
    final gateway = ScriptableGateway();
    final snapshot = await gateway.poll(const ChannelTarget('general'));
    expect(snapshot.name, 'general');
  });
}
