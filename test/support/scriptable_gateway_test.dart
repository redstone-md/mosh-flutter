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

  // Attachment SEND seam: the fake has no result to return (ADR 0024 drops
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
