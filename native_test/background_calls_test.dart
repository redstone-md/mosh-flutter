import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:mosh/src/features/background/android_waiting_owner.dart';
import 'package:mosh/src/features/background/background_commands.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:mosh/src/rust/api/private_dm.dart' as dm;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/persistence/background_delivery.dart';
import 'package:mosh/src/rust/frb_generated.dart';
import 'support/native_peer.dart';

Future<void> until(bool Function() ready, {String phase = 'call state'}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 50));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for $phase');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _Host {
  static const channel = MethodChannel('app.mosh.mosh/waiting');
  final posted = <Map<Object?, Object?>>[];
  final actions = <Map<String, Object>>[];
  late final platform = AndroidWaitingPlatform();
  late final owner = AndroidWaitingOwner(platform, BackgroundCommands());
  late final NativePeer peer;
  late final String session;
  late final String _executable;
  var revision = 0;
  var refuseMessages = false;
  var refuseCalls = false;
  var interactive = true, waitingEnabled = false;
  var callInteractive = true;

  Future<void> start() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'publishNotification') {
        final value = call.arguments as Map<Object?, Object?>;
        posted.add(value);
        if (value['kind'] == 'message' && refuseMessages) return 'blocked';
        if (value['kind'] == 'call' && refuseCalls) return 'blocked';
        return 'posted';
      }
      if (call.method == 'takeCallActions') {
        final taken = List.of(actions);
        actions.clear();
        return taken;
      }
      return {
        'revision': ++revision,
        'intentRevision': 1,
        'interactive': interactive,
        'callInteractive': callInteractive,
        'waitingEnabled': waitingEnabled,
        'serviceRunning': waitingEnabled,
        'setupComplete': true,
        'notificationsAllowed': true,
        'batteryExempt': false,
        'restriction': null
      };
    });
    _executable = Directory('mosh-core/target/debug/deps')
        .listSync()
        .whereType<File>()
        .firstWhere((file) =>
            file.uri.pathSegments.last.startsWith('android_background-') &&
            (Platform.isWindows
                ? file.path.endsWith('.exe')
                : !file.uri.pathSegments.last.contains('.')))
        .absolute
        .path;
    peer = await NativePeer.start(api: true, executable: _executable);
    session = await connect(peer);
    await owner.attach();
  }

  Future<String> connect(NativePeer installation) async {
    final invite = await dm.createInvite(
        request: const StartSessionRequest(
            displayName: 'Real phone installation', listenPort: 0));
    final id = invite.sessionId;
    await installation
        .ask({'action': 'dm_accept', 'argument': invite.inviteUri});
    final deadline = DateTime.now().add(const Duration(seconds: 50));
    while (true) {
      final local = await dm.pollSession(sessionId: id);
      final remote =
          await installation.ask({'action': 'dm_poll', 'argument': id});
      if (local.state == DmSessionState.connected &&
          remote['state'] == 'connected') break;
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
            'Call peers did not connect: ${local.state}, ${remote['state']}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return id;
  }

  Future<BackgroundNotification> prepareUnacknowledgedCallEnd() async {
    refuseCalls = true;
    final other = await NativePeer.start(api: true, executable: _executable);
    try {
      final id = await connect(other);
      final started = await other.ask({'action': 'call_start', 'argument': id});
      await until(() => posted.any((value) => value['phase'] == 'incoming'),
          phase: 'another incoming call');
      await other.ask({
        'action': 'call_end',
        'argument': id,
        'call_id': started['call_id']
      });
      await until(() => posted.any((value) => value['phase'] == 'ended'),
          phase: 'another call cancellation');
      final pending = await owner.commands.pending();
      return pending.singleWhere((entry) => entry.target.id == id);
    } finally {
      await other.close();
    }
  }

  Future<void> checkUnrelatedCallEnd(BackgroundNotification old) async {
    final pending = await owner.commands.pending();
    final active = pending.singleWhere((entry) =>
        entry.target.id == session && entry.call?.phase.name == 'active');
    await owner.calls.publish(active);
    expect(owner.calls.snapshot?.activeCall?.callId, active.call!.callId);
    await owner.calls.publish(old);
    expect(owner.calls.snapshot?.activeCall?.callId, active.call!.callId,
        reason: 'an unrelated cancellation cannot remove the current call');
    refuseCalls = false;
    await owner.refresh();
  }

  Future<void> action(String capability, {bool answer = false}) async {
    actions.add({'capability': capability, 'interactiveAnswer': answer});
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec()
                .encodeMethodCall(const MethodCall('callActionsChanged')),
            (_) {});
    await owner.refresh();
  }

  Future<void> checkMessageDelivery() async {
    refuseMessages = true;
    interactive = false;
    waitingEnabled = true;
    await platform.refresh();
    await owner.refresh();
    await dm.setReadReceiptsEnabled(enabled: true);
    await peer.ask({'action': 'dm_receipts', 'enabled': true});
    await peer.ask({
      'action': 'dm_send',
      'argument': session,
      'body': 'A real background message'
    });
    await until(() => posted.any((value) => value['kind'] == 'message'),
        phase: 'background message publication');
    await owner.refresh();
    final pending = await owner.commands.pending();
    expect(pending, hasLength(1));
    expect(pending.single.text, 'A real background message');
    final first = posted.firstWhere((value) => value['kind'] == 'message');
    refuseMessages = false;
    await owner.refresh();
    expect(await owner.commands.pending(), isEmpty);
    final replay = posted.lastWhere((value) => value['kind'] == 'message');
    expect(replay['id'], first['id']);
    expect(replay['revision'], first['revision']);
    final sent = await peer.ask({'action': 'dm_poll', 'argument': session});
    final rows = sent['messages'] as List<dynamic>;
    final message = rows
        .cast<Map<String, dynamic>>()
        .firstWhere((row) => row['body'] == 'A real background message');
    expect(message['read'], isNot(true));
    expect(owner.failure, isNull);
  }

  Future<void> close() async {
    owner.dispose();
    platform.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await peer.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('mosh-native-call-host-');
    final name = Platform.isWindows
        ? 'mosh_core.dll'
        : Platform.isMacOS
            ? 'libmosh_core.dylib'
            : 'libmosh_core.so';
    await RustLib.init(
        externalLibrary: ExternalLibrary.open('mosh-core/target/debug/$name'));
    await dm.setAppDataDir(path: directory.path);
    await dm.setHistoryDek(dek: List.filled(32, 79));
  });
  tearDownAll(() async {
    RustLib.dispose();
    if (!Platform.isWindows) await directory.delete(recursive: true);
  });

  test('real bridge call and message intake uses no chat widget or list poll',
      () async {
    final host = _Host();
    await host.start();
    addTearDown(host.close);
    final old = await host.prepareUnacknowledgedCallEnd();
    final started =
        await host.peer.ask({'action': 'call_start', 'argument': host.session});
    final callId = started['call_id'];
    await until(() =>
        host.posted
            .where((entry) => entry['phase'] == 'incoming')
            .map((entry) => entry['id'])
            .toSet()
            .length ==
        2);
    final incoming =
        host.posted.lastWhere((entry) => entry['phase'] == 'incoming');
    expect(incoming['id'], startsWith('background-call-'));
    expect(incoming.containsKey('sessionId'), false);
    expect(incoming.containsKey('callId'), false);
    host.interactive = false;
    host.waitingEnabled = true;
    await host.platform.refresh();
    await host.owner.refresh();
    expect(host.owner.platform.state!.interactive, false);
    expect(host.owner.platform.state!.callInteractive, true);
    final accepted = Completer<void>();
    host.owner.calls.onAnswer = (session, call) async {
      await dm.callAccept(sessionId: session, callId: call);
      accepted.complete();
    };
    await host.action(incoming['answerCapability'] as String, answer: true);
    await accepted.future.timeout(const Duration(seconds: 30));
    await until(() => host.posted.any((entry) => entry['phase'] == 'active'));
    final active = host.posted.lastWhere((entry) => entry['phase'] == 'active');
    await host.checkUnrelatedCallEnd(old);
    expect(host.owner.calls.snapshot?.activeCall?.callId, callId);
    await host.action(active['hangupCapability'] as String);
    await until(() =>
        host.owner.calls.snapshot == null &&
        host.posted.any((entry) => entry['phase'] == 'ended'));
    await host.action(incoming['answerCapability'] as String, answer: true);
    expect(host.owner.calls.snapshot, isNull);
    await host.checkMessageDelivery();
    expect(host.owner.failure, isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
