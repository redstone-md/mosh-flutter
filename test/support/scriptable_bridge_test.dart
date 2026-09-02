// Unit test for the bridge-facade test double itself: the canned invite
// flow and the consent store against its in-memory state, and the one
// shared-state rule with the gateway double -- both surfaces are views over
// one runtime.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/channel_runtime.dart' show JoinChannelRequest;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

import 'gateway_snapshots.dart';
import 'scriptable_gateway.dart';
import 'scriptable_bridge.dart';

void main() {
  test('the test bridge createInvite -> listSessions -> leave round trip',
      () async {
    final bridge = ScriptableBridge();
    final invite = await bridge.createInvite(
      request:
          const StartSessionRequest(displayName: 'alice', listenPort: 8765),
    );
    expect(
        invite.inviteUri, startsWith('mosh://invite?mesh=fakemesh&session='));
    expect(invite.inviteUri, contains('#fp='));

    final listed = await bridge.listSessions();
    expect(listed.sessions.map((s) => s.sessionId), contains(invite.sessionId));

    // Leaving is a seam call, so the proof runs through the gateway double
    // sharing the bridge's state: the list read must see the removal.
    final gateway = ScriptableGateway(conversations: bridge.conversations);
    await gateway.leave(DmTarget(invite.sessionId));
    final remaining = await bridge.listSessions();
    expect(remaining.sessions.map((s) => s.sessionId),
        isNot(contains(invite.sessionId)));
  });

  test('the test bridge shares the gateway double\'s conversation state',
      () async {
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    gateway.seedSessions([
      fakeSession(
        sessionId: 'dm-1',
        displayName: 'me',
        role: 'inviter',
        inviteUri: '',
        fingerprint: 'fp',
      ),
    ]);

    // The bridge's list serves what the gateway seeded...
    final listed = await bridge.listSessions();
    expect(listed.sessions.map((s) => s.sessionId), contains('dm-1'));

    // ...and an invite the bridge accepts is a session the gateway polls.
    final accepted = await bridge.acceptInvite(
      request: const AcceptInviteRequest(
        inviteUri: 'mosh://invite?session=x#fp=FP',
        displayName: 'bob',
        listenPort: 8765,
      ),
    );
    final snapshot = await gateway.poll(DmTarget(accepted.sessionId));
    expect(snapshot.sessionId, accepted.sessionId);
    expect(snapshot.role, 'invitee');
  });

  test(
      'the test bridge setVpnBypassConsent stores what getVpnBypassConsent reads',
      () async {
    final bridge = ScriptableBridge();
    expect(await bridge.getVpnBypassConsent(), isNull);
    await bridge.setVpnBypassConsent(interfaceName: 'eth0');
    expect((await bridge.getVpnBypassConsent())?.interface_, 'eth0');
    await bridge.setVpnBypassConsent(interfaceName: null);
    expect(await bridge.getVpnBypassConsent(), isNull);
  });

  test('the test bridge joinChannel falls back to the canned snapshot',
      () async {
    final bridge = ScriptableBridge();
    final snapshot = await bridge.joinChannel(
      request: const JoinChannelRequest(
        name: 'general',
        displayName: '',
        listenPort: 8765,
      ),
    );
    expect(snapshot.name, 'general');
  });

  // The outbound DM-offer sends no-op (no real peer to deliver to, matching
  // the dismiss pair on the seam). Both must complete normally with no
  // throw so the popover UI resolves.
  test('the test bridge sendChannelDmOffer completes (no-op)', () async {
    final bridge = ScriptableBridge();
    await bridge.sendChannelDmOffer(
      channelName: 'test',
      peerFingerprint: 'FP',
      inviteUri: 'mosh://invite?mesh=fakemesh&session=fake-session#fp=FP',
    );
  });

  test('the test bridge sendGroupDmOffer completes (no-op)', () async {
    final bridge = ScriptableBridge();
    await bridge.sendGroupDmOffer(
      groupId: 'g',
      peerFingerprint: 'FP',
      inviteUri: 'mosh://invite?mesh=fakemesh&session=fake-session#fp=FP',
    );
  });

  // FU-1: NativeRuntimeStatus is constructible in pure Dart (the five
  // sub-structs are non-opaque across flutter_rust_bridge), so the bridge
  // double's canned status carries real, field-readable values instead of
  // throwing UnsupportedError.
  test('the test bridge nativeRuntimeStatus returns real readable fields',
      () async {
    final status = await ScriptableBridge().nativeRuntimeStatus();

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
}
