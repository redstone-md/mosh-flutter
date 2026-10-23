// Measurement-only client of the exact FRB API shipped in the installer.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:mosh/src/rust/frb_generated.dart';
import 'package:mosh/src/rust/api/private_dm.dart' as dm;
import 'package:mosh/src/rust/api/private_group.dart' as groups;
import 'package:mosh/src/rust/api/channel.dart' as channels;
import 'package:mosh/src/rust/api/device_link.dart' as devices;
import 'package:mosh/src/rust/api/plus.dart' as plus;
import 'package:mosh/src/rust/api/org.dart' as orgs;
import 'package:mosh/src/rust/api/conversation.dart' as conversation;
import 'package:mosh/src/rust/api/conversation/names.dart' as names;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/channel_runtime.dart';

Future<void> main(List<String> args) async {
  if (args.singleOrNull == '--validate') {
    stdout.writeln('AOT client validated');
    return;
  }
  await RustLib.init(externalLibrary: ExternalLibrary.open(args[0]));
  await dm.setAppDataDir(path: args[1]);
  if (args[2] == 'counterpart') {
    await dm.setHistoryDek(dek: List.filled(32, 93));
  }
  await devices.snapshot();
  await orgs.list();
  final pin = Platform.environment['MOSH_PLUS_ISSUER_KEY'];
  if (pin != null && pin.isNotEmpty) {
    await plus.configureMainnetIssuer(publicKeyB64: pin);
  }
  reply({'ready': true});
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    try {
      final input = jsonDecode(line) as Map<String, dynamic>;
      reply(await command(input));
    } catch (error) {
      reply({'error': error.toString()});
    }
  }
}

void reply(Map<String, Object?> result) =>
    stdout.writeln('IDLE_REPLY ${jsonEncode(result)}');

Future<Map<String, Object?>> command(Map<String, dynamic> input) async {
  final op = input['op'] as String;
  switch (op) {
    case 'invite':
      final value = await dm.createInvite(
          request: const StartSessionRequest(
              displayName: 'Profile owner', listenPort: 55005));
      final snapshot = await dm.pollSession(sessionId: value.sessionId);
      return {
        'session': value.sessionId,
        'uri': value.inviteUri,
        'port': snapshot.mesh!.listenPort,
      };
    case 'accept':
      final value = await dm.acceptInvite(
          request: AcceptInviteRequest(
              inviteUri: input['uri'] as String,
              displayName: input['name'] as String,
              listenPort: input['port'] as int,
              staticPeer: input['peer'] as String));
      return {'session': value.sessionId};
    case 'poll':
      return summarize(
          await dm.pollSession(sessionId: input['session'] as String));
    case 'send':
      await conversation.send(
          reference: conversation.BridgeConversationRef(
              kind: conversation.BridgeConversationKind.dm,
              id: input['session'] as String),
          body: input['body'] as String);
      return {'sent': true};
    case 'seed':
      await seed(input['channel'] as String);
      return {'seeded': true};
    case 'read':
      await names.personalNames();
      final sessions = await dm.listSessions();
      final groupList = await groups.list();
      final channelList = await channels.list();
      if (input['session'] case final String session) {
        await dm.pollSession(sessionId: session);
      }
      return {
        'dm': sessions.sessions.length,
        'groups': groupList.groups.length,
        'channels': channelList.channels.length
      };
    case 'plus':
      await plus.snapshot();
      return {'ok': true};
    case 'inventory':
      final inventory = await dm.listSessions();
      return {
        'pending_invitations': (await dm.listPendingInvites()).length,
        'bodies': [
          for (final session in inventory.sessions)
            for (final message in session.messages) message.body,
        ]..sort(),
      };
    case 'exit':
      exit(0);
    default:
      throw ArgumentError('Unknown profiling operation');
  }
}

Map<String, Object?> summarize(SessionSnapshot snapshot) => {
      'state': snapshot.state.name,
      'transport': snapshot.transport.name,
      'mesh_peers': snapshot.mesh?.peerCount,
      'messages': [
        for (final m in snapshot.messages)
          {'body': m.body, 'status': m.deliveryStatus?.name}
      ],
    };

Future<void> seed(String name) async {
  for (var i = 0; i < 2; i++) {
    await groups.createGroup(
        request: CreateGroupRequest(
            displayName: 'Profile owner',
            label: 'Profile group $i',
            listenPort: 55005));
  }
  await channels.join(
      request: JoinChannelRequest(
          name: name, displayName: 'Profile owner', listenPort: 55005));
}
