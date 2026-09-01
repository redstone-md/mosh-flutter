// Real-bridge dispatch proof for the six shared conversation actions.
//
// The widget suite runs on ScriptableGateway because the Rust runtime is not
// linkable there. This file is the exception that runs when the native libs
// ARE present: `flutter test` from the repo root loads
// `mosh-core/target/release/mosh_core.dll` -- the ioDirectory the generated
// loader config names, which is why a release build is required
// (`cargo build --release --manifest-path mosh-core/Cargo.toml`) -- and that
// runtime dlopens `moss-runtime/moss.dll` from the repo root. Without either
// library the tests skip, so CI's flutter-test job (which never builds the
// Rust side) is unaffected and the deep proof stays available locally and
// wherever the libs are built.
//
// What they prove, per conversation kind, through RealBridgeGateway and the
// shared `api::conversation` functions (ADR 0024): the one
// ConversationTarget -> BridgeConversationRef conversion dispatches each of
// the six actions to the RIGHT runtime. A wrong kind mapping would write the
// message into a different runtime's store, and the poll below would miss
// it. Failures surface as typed ConversationBridgeErrors, never bare
// strings.
//
// Solo conversations have no peer, so the transfer-state paths (an
// attachment send past its readiness gate, a download of an id nobody
// holds) cannot be exercised positively here. For those the tests pin the
// guarantees the bridge does make without a peer: undecodable bytes are
// `InvalidInput` before any runtime is touched, and a missing id answers
// with the typed error -- never a bare string.

import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/gateway/real_bridge_gateway.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart';
import 'package:mosh/src/rust/channel_runtime.dart' show JoinChannelRequest;
import 'package:mosh/src/rust/frb_generated.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart'
    show CreateGroupRequest;

const _coreDll = 'mosh-core/target/release/mosh_core.dll';
const _mossDll = 'moss-runtime/moss.dll';

void main() {
  final nativeReady =
      File(_coreDll).existsSync() && File(_mossDll).existsSync();
  final skip =
      !nativeReady ? 'native libs not built: $_coreDll / $_mossDll' : false;

  setUpAll(() async {
    if (!nativeReady) return;
    await RustLib.init();
  });

  test(
    'undecodable attachment bytes cross as the typed error on every kind',
    () async {
      final gateway = RealBridgeGateway();
      // The bytes die at the bridge door before any runtime lookup, so this
      // call is safe against all three arms of the dispatch.
      for (final target in <AnyConversationTarget>[
        const DmTarget('no-such-session'),
        const ChannelTarget('no-such-channel'),
        const GroupTarget('no-such-group'),
      ]) {
        await expectLater(
          gateway.sendAttachment(
            target,
            fileName: 'x.txt',
            mime: 'text/plain',
            dataBase64: '!!! not base64 !!!',
          ),
          throwsA(isA<ConversationBridgeError>()),
          reason: 'sendAttachment on $target must cross the typed seam',
        );
      }
    },
    skip: skip,
  );

  test(
    'dm: send lands in the DM runtime; a missing id answers typed',
    () async {
      final gateway = RealBridgeGateway();
      final invite = await gateway.createInvite(
        request: const StartSessionRequest(
          displayName: 'dispatch-proof',
          listenPort: 0,
        ),
      );
      final dm = DmTarget(invite.sessionId);
      await gateway.send(dm, body: 'dm dispatch');
      final snap = await gateway.poll(dm);
      expect(
        snap.messages.any((m) => m.body == 'dm dispatch'),
        isTrue,
        reason: 'a DmTarget send must land in the DM runtime',
      );
      await expectLater(
        gateway.downloadAttachment(dm, attachmentId: 'no-such-attachment'),
        throwsA(isA<ConversationBridgeError>()),
        reason: 'the DM arm must answer with the typed bridge error',
      );
      await gateway.leave(dm);
    },
    skip: skip,
  );

  test(
    'channel: send lands in the channel runtime',
    () async {
      final gateway = RealBridgeGateway();
      // Joined solo, so no peer is needed to record the send.
      final name = 'dispatch-${DateTime.now().millisecondsSinceEpoch}';
      final channel = ChannelTarget(name);
      await gateway.joinChannel(
        request: JoinChannelRequest(
          name: name,
          displayName: name,
          listenPort: 0,
        ),
      );
      await gateway.send(channel, body: 'channel dispatch');
      final snap = await gateway.poll(channel);
      expect(
        snap.messages.any((m) => m.body == 'channel dispatch'),
        isTrue,
        reason: 'a ChannelTarget send must land in the channel runtime',
      );
      await gateway.leave(channel);
    },
    skip: skip,
  );

  test(
    'group: send lands in the group runtime; after leave the lookup misses',
    () async {
      final gateway = RealBridgeGateway();
      final created = await gateway.createGroup(
        request: const CreateGroupRequest(
          displayName: 'dispatch-proof-group',
          listenPort: 0,
        ),
      );
      final group = GroupTarget(created.groupId);
      await gateway.send(group, body: 'group dispatch');
      final snap = await gateway.poll(group);
      expect(
        snap.messages.any((m) => m.body == 'group dispatch'),
        isTrue,
        reason: 'a GroupTarget send must land in the group runtime',
      );
      await gateway.leave(group);
      // The poll may still read a closed snapshot; the write cannot.
      await expectLater(
        gateway.send(group, body: 'after leave'),
        throwsA(isA<ConversationBridgeError>()),
      );
    },
    skip: skip,
  );
}
