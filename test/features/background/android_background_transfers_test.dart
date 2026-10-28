import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/background/android_background_transfers.dart';
import 'package:mosh/src/features/background/background_commands.dart';
import 'package:mosh/src/features/background/background_execution_mirror.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:mosh/src/rust/api/conversation.dart';
import 'package:mosh/src/rust/persistence/user_transfers/types.dart';
import '../../support/background_status.dart';

const id = 'transfer-0123456789abcdef0123456789abcdef';
const target = BridgeConversationRef(
    kind: BridgeConversationKind.dm, id: 'private-target');
UserTransfer transfer(UserTransferState state,
        {UserTransferDirection direction = UserTransferDirection.upload}) =>
    UserTransfer(
        id: id,
        target: target,
        attachmentId: 'private-attachment',
        direction: direction,
        state: state,
        completedBytes: BigInt.zero,
        totalBytes: BigInt.from(3),
        revision: BigInt.one);

class Commands extends BackgroundCommands {
  Commands(this.events);
  final List<String> events;
  bool refuseCancel = false;
  @override
  Future<UserTransfer> prepareTransfer(BridgeConversationRef target,
      UserTransferDirection direction, String? attachment, BigInt size) async {
    events.add('prepare:${direction.name}:$size');
    return transfer(UserTransferState.prepared, direction: direction);
  }

  @override
  Future<void> sendTransfer(String id, BridgeAttachmentPayload payload) async {
    events.add('send');
  }

  @override
  Future<void> downloadTransfer(String id) async {
    events.add('download');
  }

  @override
  Future<void> cancelTransfer(String id) async {
    events.add('cancel');
    if (refuseCancel) throw StateError('Durable storage refused');
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> events;
  late List<MethodCall> calls;
  late List<Object?> actions;
  setUp(() {
    events = [];
    calls = [];
    actions = [];
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidWaitingPlatform.channel, (call) async {
      calls.add(call);
      if (call.method.startsWith('begin')) {
        events.add(call.method);
        return false;
      }
      if (call.method == 'takeTransferActions') return actions;
      if (call.method == 'acknowledgeTransferActions') {
        events.add('ack');
        actions = [];
        return null;
      }
      return {
        'revision': 1,
        'intentRevision': 1,
        'interactive': false,
        'waitingEnabled': false,
        'serviceRunning': false,
        'setupComplete': true,
        'notificationsAllowed': true,
        'batteryExempt': false
      };
    });
  });
  tearDown(() => binding.defaultBinaryMessenger
      .setMockMethodCallHandler(AndroidWaitingPlatform.channel, null));

  test(
      'native admission precedes OS scheduling and a visible transfer survives scheduler refusal',
      () async {
    final platform = AndroidWaitingPlatform();
    addTearDown(platform.dispose);
    final owner = AndroidBackgroundTransfers(Commands(events), platform);
    await owner.send(
        target,
        const BridgeAttachmentPayload(
            fileName: 'private-file', mime: 'text/plain', dataBase64: 'YWJj'));
    expect(events, ['prepare:upload:3', 'beginUserTransfer', 'send']);
    expect(calls.single.arguments,
        {'id': id, 'direction': 'upload', 'estimatedBytes': 3});
    events.clear();
    calls.clear();
    await owner.download(target, 'private-attachment');
    expect(events, ['prepare:download:0', 'beginUserTransfer', 'download']);
  });

  test('OS Cancel is acknowledged only after native durable acceptance',
      () async {
    final platform = AndroidWaitingPlatform();
    addTearDown(platform.dispose);
    final commands = Commands(events)..refuseCancel = true;
    final owner = AndroidBackgroundTransfers(commands, platform);
    actions = [
      {'id': id, 'action': 'cancel', 'revision': 9}
    ];
    await expectLater(owner.flushActions(), throwsStateError);
    expect(events, ['cancel']);
    expect(actions, isNotEmpty);
    commands.refuseCancel = false;
    await owner.flushActions();
    expect(events, ['cancel', 'cancel', 'ack']);
    expect(calls.last.arguments, [
      {'id': id, 'revision': 9}
    ]);
  });

  test('restored native facts mirror only opaque execution metadata', () async {
    final platform = AndroidWaitingPlatform();
    addTearDown(platform.dispose);
    await BackgroundExecutionMirror(platform).update(
        backgroundStatus(transfers: [transfer(UserTransferState.paused)]), 7);
    final facts = calls.single.arguments as Map;
    expect(facts['intentRevision'], 7);
    expect(facts['transfers'], [
      {
        'id': id,
        'direction': 'upload',
        'state': 'paused',
        'completedBytes': 0,
        'totalBytes': 3
      }
    ]);
    expect(facts.toString(), isNot(contains('private-target')));
  });

  test(
      'only native pending uploads schedule a coalesced deferred job while waiting stays off',
      () async {
    final platform = AndroidWaitingPlatform();
    addTearDown(platform.dispose);
    await platform.refresh();
    calls.clear();
    final owner = AndroidBackgroundTransfers(Commands(events), platform);
    for (final state in [
      UserTransferState.prepared,
      UserTransferState.waitingReceiver,
      UserTransferState.paused
    ]) {
      await owner
          .scheduleDeferred(backgroundStatus(transfers: [transfer(state)]));
    }
    expect(calls, isEmpty);
    final status = backgroundStatus(
        transfers: [transfer(UserTransferState.waitingExecution)]);
    await owner.scheduleDeferred(status);
    await owner.scheduleDeferred(status);
    expect(calls.map((call) => call.method), ['beginDeferredTransfer']);
    expect(platform.state!.waitingEnabled, false);
  });
}
