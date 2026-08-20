// Unit test for the shared test gateway itself: the canned invite flow,
// the message append, and the session teardown against its in-memory state.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'scriptable_gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

void main() {
  test('the test gateway createInvite -> send -> leave round trip', () async {
    final gateway = ScriptableGateway();
    final invite = await gateway.createInvite(
      request:
          const StartSessionRequest(displayName: 'alice', listenPort: 8765),
    );
    expect(
        invite.inviteUri, startsWith('mosh://invite?mesh=fakemesh&session='));
    expect(invite.inviteUri, contains('#fp='));

    final listed = await gateway.listSessions();
    expect(listed.sessions.map((s) => s.sessionId), contains(invite.sessionId));

    final target = DmTarget(invite.sessionId);
    final before = (await gateway.poll(target)).messages.length;
    await gateway.send(target, body: 'hi');
    final appended = await gateway.poll(target);
    expect(appended.messages.length, before + 1);
    expect(appended.messages.last.body, 'hi');

    await gateway.leave(target);
    final remaining = await gateway.listSessions();
    expect(remaining.sessions.map((s) => s.sessionId),
        isNot(contains(invite.sessionId)));
  });

  // FU-1: NativeRuntimeStatus is now constructible in pure Dart (the five
  // sub-structs are non-opaque across flutter_rust_bridge), so the gateway
  // returns a real snapshot instead of throwing UnsupportedError.
  test('the test gateway nativeRuntimeStatus returns real readable fields',
      () async {
    final gateway = ScriptableGateway();
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
  test('the test gateway DM sendAttachment returns a canned result', () async {
    final gateway = ScriptableGateway();
    final result = await gateway.sendAttachment(
      const DmTarget('fake-session-1'),
      fileName: 'photo.png',
      mime: 'image/png',
      dataBase64: 'iVBORw0KGgo=',
      thumbnailBase64: 'thumb',
    );
    expect(result.conversationId, 'fake-dm:fake-session-1');
    expect(result.attachmentId, contains('fake-dm-attachment:'));
    // contentHash is the data-base64 hashCode -- stable + deterministic.
    expect(result.contentHash, isNotEmpty);
  });

  // Peer-DM-offer SEND seams (channel/group): the fake no-ops (no real peer
  // to deliver to, matching the dismiss pair). Both must complete normally
  // with no throw so the popover UI resolves.
  test('the test gateway sendChannelDmOffer completes (no-op)', () async {
    final gateway = ScriptableGateway();
    await gateway.sendChannelDmOffer(
      channelName: 'test',
      peerFingerprint: 'FP',
      inviteUri: 'mosh://invite?mesh=fakemesh&session=fake-session#fp=FP',
    );
  });

  test('the test gateway sendGroupDmOffer completes (no-op)', () async {
    final gateway = ScriptableGateway();
    await gateway.sendGroupDmOffer(
      groupId: 'g',
      peerFingerprint: 'FP',
      inviteUri: 'mosh://invite?mesh=fakemesh&session=fake-session#fp=FP',
    );
  });
}
