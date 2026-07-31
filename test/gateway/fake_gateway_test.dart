// S4.1: focused unit test for FakeGateway. Mirrors the existing flutter_test
// pattern (see test/util/format_test.dart). Verifies the canned invite flow,
// message append, and session teardown against the in-memory state.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

void main() {
  test('FakeGateway createInvite -> sendMessage -> closeSession round trip',
      () async {
    final gateway = FakeGateway();
    final invite = await gateway.createInvite(
      request: const StartSessionRequest(displayName: 'alice', listenPort: 8765),
    );
    expect(invite.inviteUri, startsWith('mosh://invite?mesh=fakemesh&session='));
    expect(invite.inviteUri, contains('#fp='));

    final listed = await gateway.listSessions();
    expect(listed.sessions.map((s) => s.sessionId), contains(invite.sessionId));

    final before = (await gateway.pollSession(sessionId: invite.sessionId)).messages.length;
    final result = await gateway.sendMessage(sessionId: invite.sessionId, body: 'hi');
    expect(result.deliveryStatus, MessageDeliveryStatus.sent);
    final after = (await gateway.pollSession(sessionId: invite.sessionId)).messages.length;
    expect(after, before + 1);

    final closed = await gateway.closeSession(sessionId: invite.sessionId);
    expect(closed.closed, isTrue);
    final remaining = await gateway.listSessions();
    expect(remaining.sessions.map((s) => s.sessionId), isNot(contains(invite.sessionId)));
  });
}
