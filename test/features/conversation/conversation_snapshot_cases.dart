// Mapping the three generated snapshots into one view, and the provider
// that does it.
//
// The interesting part is "own": a DM decides it by device name, a channel
// and a group by fingerprint, because two members can share a display name
// but never a fingerprint.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart' show CallEvent;
import 'package:mosh/src/rust/conversation/attachments.dart'
    show AttachmentState, AttachmentView;
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/conversation_cases.dart';
import '../../support/scriptable_gateway.dart';

/// Reads the mapped view for [testCase] out of a container built with its own
/// snapshot override.
Future<ConversationSnapshot> _read(
  ConversationCase testCase, {
  List<TestMessage> messages = const [],
  List<AttachmentView> attachments = const [],
}) async {
  final container = ProviderContainer(overrides: [
    gatewayProvider.overrideWithValue(ScriptableGateway()),
    testCase.snapshotOverride(messages: messages, attachments: attachments),
  ]);
  addTearDown(container.dispose);
  return container.read(conversationSnapshotProvider(testCase.target).future);
}

void main() {
  test('a DM decides own by device name and carries no fingerprint', () async {
    final dm = conversationCases().first;
    final snapshot = await _read(dm, messages: const [
      TestMessage.own(body: 'mine'),
      TestMessage(body: 'theirs'),
    ]);

    expect(snapshot, isA<DmConversation>());
    expect(snapshot.messages.map((m) => m.own), [true, false]);
    expect(snapshot.messages.map((m) => m.fromFingerprint), [null, null]);
    // With no fingerprint, rows group by device name instead.
    expect(snapshot.messages.map((m) => m.senderKey), [ownDevice, 'peer']);
  });

  test('a DM keeps the call event on the message', () async {
    final dm = conversationCases().first;
    final snapshot = await _read(dm, messages: [
      TestMessage(
        body: '',
        callEvent: CallEvent(
          kind: 'missed',
          durationMs: BigInt.zero,
          callId: 'c1',
        ),
      ),
    ]);

    expect(snapshot.messages.single.callEvent?.kind, 'missed');
  });

  for (final testCase in conversationCases().skip(1)) {
    test('a ${testCase.label} decides own by fingerprint', () async {
      final snapshot = await _read(testCase, messages: const [
        TestMessage.own(body: 'mine'),
        // Same display name as the local device, different fingerprint.
        TestMessage(
          fromDevice: ownDevice,
          fromFingerprint: 'fp-impostor',
          body: 'not mine',
        ),
      ]);

      expect(snapshot.messages.map((m) => m.own), [true, false]);
      expect(
        snapshot.messages.map((m) => m.senderKey),
        [ownFingerprint, 'fp-impostor'],
      );
    });
  }

  for (final testCase in conversationCases()) {
    test('${testCase.label}: the view keeps its own source snapshot', () async {
      final snapshot = await _read(testCase);
      expect(snapshot.target, testCase.target);
      expect(snapshot.ownDeviceName, ownDevice);
      expect(
        snapshot,
        switch (testCase.target.kind) {
          ConversationKind.dm => isA<DmConversation>(),
          ConversationKind.channel => isA<ChannelConversation>(),
          ConversationKind.group => isA<GroupConversation>(),
        },
      );
    });

    test('${testCase.label}: an attachment finds its transfer state', () async {
      final file = testAttachment(attachmentId: 'att-1');
      final snapshot = await _read(
        testCase,
        messages: [TestMessage(body: 'here', attachment: file)],
        attachments: [
          testAttachmentView(
            attachmentId: 'att-1',
            state: AttachmentState.downloading,
          ),
        ],
      );

      expect(
        snapshot.attachmentView('att-1')?.state,
        AttachmentState.downloading,
      );
      expect(snapshot.attachmentView('att-missing'), isNull);
    });
  }

  group('canRetry', () {
    Future<ConversationMessage> message(
      ConversationCase testCase, {
      bool own = true,
      MessageDeliveryStatus? status = MessageDeliveryStatus.failed,
      bool? retryable = true,
      String? messageId = 'm1',
      String? error = 'peer offline',
    }) async {
      final snapshot = await _read(testCase, messages: [
        TestMessage(
          fromDevice: own ? ownDevice : 'peer',
          fromFingerprint: own ? ownFingerprint : 'fp-peer',
          body: 'boom',
          deliveryStatus: status,
          deliveryError: error,
          retryable: retryable,
          messageId: messageId,
        ),
      ]);
      final mapped = snapshot.messages.single;
      expect(mapped.body, 'boom', reason: testCase.label);
      expect(mapped.own, own, reason: testCase.label);
      expect(mapped.deliveryStatus, status, reason: testCase.label);
      expect(mapped.deliveryError, error, reason: testCase.label);
      expect(mapped.retryable, retryable, reason: testCase.label);
      expect(mapped.messageId, messageId, reason: testCase.label);
      return mapped;
    }

    test('an own failed message the runtime will retry can be retried',
        () async {
      for (final testCase in conversationCases()) {
        expect((await message(testCase, error: '  peer offline  ')).canRetry,
            isTrue,
            reason: testCase.label);
        expect((await message(testCase, error: null)).canRetry, isTrue,
            reason: testCase.label);
      }
    });

    test("someone else's message cannot", () async {
      for (final testCase in conversationCases()) {
        expect((await message(testCase, own: false)).canRetry, isFalse,
            reason: testCase.label);
      }
    });

    test('a message that did not fail cannot', () async {
      for (final testCase in conversationCases()) {
        expect(
            (await message(testCase, status: MessageDeliveryStatus.sent))
                .canRetry,
            isFalse,
            reason: testCase.label);
      }
    });

    test('a failure the runtime will not retry cannot', () async {
      for (final testCase in conversationCases()) {
        expect((await message(testCase, retryable: false)).canRetry, isFalse,
            reason: testCase.label);
      }
    });

    test('a message with no id cannot', () async {
      for (final testCase in conversationCases()) {
        expect((await message(testCase, messageId: null)).canRetry, isFalse,
            reason: testCase.label);
      }
    });
  });
}
