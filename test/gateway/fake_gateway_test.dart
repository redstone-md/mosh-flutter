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

  // FU-1: NativeRuntimeStatus is now constructible in pure Dart (the five
  // sub-structs are non-opaque across flutter_rust_bridge), so FakeGateway
  // returns a real snapshot instead of throwing UnsupportedError.
  test('FakeGateway nativeRuntimeStatus returns real readable fields',
      () async {
    final gateway = FakeGateway();
    final status = await gateway.nativeRuntimeStatus();

    expect(status.moss.linkMode, 'dynamic');
    expect(status.moss.available, isTrue);
    expect(status.secureStorage.backend, 'os-keychain');
    expect(status.secureStorage.available, isTrue);
    expect(status.persistence.available, isFalse);
    // OpenMLS smoke + roundtrip report success (ok set, error null).
    expect(status.openmlsSmoke.error, isNull);
    expect(status.openmlsSmoke.ok, isNotNull);
    expect(status.openmlsSmoke.ok!.protectedMessageCreated, isTrue);
    expect(status.openmlsRoundtrip.error, isNull);
   expect(status.openmlsRoundtrip.ok, isNotNull);
   expect(status.openmlsRoundtrip.ok!.welcomeJoined, isTrue);
   expect(status.openmlsRoundtrip.ok!.plaintextRoundtrip, isTrue);
 });

  // DM attachment SEND seam: the fake returns a canned AttachmentSendResult
  // with a deterministic attachmentId derived from the file name (so a
  // screen-level test can invalidate a snapshot family by the returned id).
  test('FakeGateway sendPrivateAttachment returns a canned result', () async {
    final gateway = FakeGateway();
    final result = await gateway.sendPrivateAttachment(
      sessionId: 'fake-session-1',
      fileName: 'photo.png',
      mime: 'image/png',
      dataBase64: 'iVBORw0KGgo=',
      thumbnailBase64: 'thumb',
    );
    expect(result.sessionId, 'fake-dm:fake-session-1');
    expect(result.attachmentId, contains('fake-dm-attachment:'));
    // contentHash is the data-base64 hashCode -- stable + deterministic.
    expect(result.contentHash, isNotEmpty);
  });
}
