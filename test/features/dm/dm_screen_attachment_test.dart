// Widget tests for the in-scope attachment card rendered inside a DM
// message bubble (lib/src/features/conversation/attachment_card.dart, wired in
// lib/src/features/dm/dm_screen.dart). Mirrors the established slice-one
// widget-test pattern: a ProviderScope override of `activeSessionProvider`
// (the public FutureProvider.family seam) returns a controlled
// SessionSnapshot, so the rendered card is deterministic and neither the
// gateway nor the native cdylib are involved.
//
// In scope: file name + formatted size + localized state label + icon +
// progress indicator, plus transfer-action busy behavior.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import 'package:mosh/src/features/shared/attachment_launcher.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

import '../shared/attachment_launcher_test_support.dart';
import '../../support/pump.dart';

AttachmentDescriptor _fileDescriptor({
  required String attachmentId,
  required String fileName,
  required String mime,
  required int totalSize,
}) =>
    AttachmentDescriptor(
      attachmentId: attachmentId,
      contentHash: 'h-$attachmentId',
      fileName: fileName,
      mime: mime,
      totalSize: BigInt.from(totalSize),
      thumbnailB64: null,
      voice: null,
    );

ChatMessage _msgWithAttachment({
  required String fromDevice,
  required String body,
  required AttachmentDescriptor attachment,
  BigInt? sentAtMs,
}) =>
    ChatMessage(
      fromDevice: fromDevice,
      body: body,
      messageId: null,
      sentAtMs: sentAtMs,
      attachment: attachment,
      callEvent: null,
      deliveryStatus: null,
      deliveryError: null,
      retryable: null,
      retryCount: null,
    );

AttachmentView _view({
  required String attachmentId,
  required String direction,
  required AttachmentState state,
  int completed = 0,
  int total = 0,
  String? localPath,
}) =>
    AttachmentView(
      attachmentId: attachmentId,
      direction: direction,
      state: state,
      completedChunks: BigInt.from(completed),
      chunkCount: BigInt.from(total),
      localPath: localPath,
    );

SessionSnapshot _snapshot({
  required String sessionId,
  required String displayName,
  required List<ChatMessage> messages,
  List<AttachmentView> attachments = const [],
}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'testmesh',
      role: 'inviter',
      displayName: displayName,
      peerDisplayName: '',
      state: 'ready',
      path: 'direct',
      relayReady: null,
      inviteUri: null,
      fingerprint: '0123456789abcdef',
      messages: messages,
      attachments: attachments,
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

Future<void> _pump(
  WidgetTester tester, {
  required String sessionId,
  required SessionSnapshot snapshot,
  ScriptableGateway? gateway,
  AttachmentLauncher? launcher,
}) =>
    pumpScreen(tester, DmScreen(sessionId: sessionId), overrides: [
      activeSessionProvider(sessionId).overrideWith((ref) async => snapshot),
      if (gateway != null) gatewayProvider.overrideWithValue(gateway),
      if (launcher != null)
        attachmentLauncherProvider.overrideWithValue(launcher),
    ]);

Finder _attachmentAction() => find.descendant(
      of: find.byType(AttachmentCard),
      matching: find.byType(IconButton),
    );

void main() {
  const sessionId = 'sess-attach';
  final base = BigInt.from(1700000000000); // 2023-11-14T22:13:20Z

  testWidgets('offered (incoming) attachment renders name, size, state label',
      (tester) async {
    final descriptor = _fileDescriptor(
      attachmentId: 'att-1',
      fileName: 'report.pdf',
      mime: 'application/pdf',
      totalSize: 1536,
    );
    final msg = _msgWithAttachment(
      fromDevice: 'bob',
      body: 'here is the report',
      attachment: descriptor,
      sentAtMs: base,
    );
    final snapshot = _snapshot(
      sessionId: sessionId,
      displayName: 'alice',
      messages: [msg],
      attachments: [
        _view(
            attachmentId: 'att-1',
            direction: 'incoming',
            state: AttachmentState.offered),
      ],
    );

    await _pump(tester, sessionId: sessionId, snapshot: snapshot);

    // File name renders (data, not localized).
    expect(find.text('report.pdf'), findsOneWidget);
    // Size renders via formatBytes(1536) -> "1.5 KB".
    expect(find.textContaining('1.5 KB'), findsOneWidget);
    // Offered state label renders (localized "Ready to download").
    expect(find.textContaining('Ready to download'), findsOneWidget);
  });

  testWidgets(
      'downloading attachment renders the percent label and a progress bar',
      (tester) async {
    final descriptor = _fileDescriptor(
      attachmentId: 'att-2',
      fileName: 'video.mp4',
      mime: 'video/mp4',
      totalSize: 10485760,
    );
    final msg = _msgWithAttachment(
      fromDevice: 'bob',
      body: 'big clip incoming',
      attachment: descriptor,
      sentAtMs: base,
    );
    final snapshot = _snapshot(
      sessionId: sessionId,
      displayName: 'alice',
      messages: [msg],
      attachments: [
        _view(
          attachmentId: 'att-2',
          direction: 'incoming',
          state: AttachmentState.downloading,
          completed: 5,
          total: 10,
        ),
      ],
    );

    await _pump(tester, sessionId: sessionId, snapshot: snapshot);

    // File name renders.
    expect(find.text('video.mp4'), findsOneWidget);
    // Downloading 50% label renders (5/10 chunks -> 50%).
    expect(find.textContaining('Downloading 50%'), findsOneWidget);
    // A linear progress indicator is present while downloading.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('failed attachment renders the failed label + error icon',
      (tester) async {
    final descriptor = _fileDescriptor(
      attachmentId: 'att-3',
      fileName: 'archive.zip',
      mime: 'application/zip',
      totalSize: 2048,
    );
    final msg = _msgWithAttachment(
      fromDevice: 'bob',
      body: 'this one broke',
      attachment: descriptor,
      sentAtMs: base,
    );
    final snapshot = _snapshot(
      sessionId: sessionId,
      displayName: 'alice',
      messages: [msg],
      attachments: [
        _view(
            attachmentId: 'att-3',
            direction: 'incoming',
            state: AttachmentState.failed),
      ],
    );

    await _pump(tester, sessionId: sessionId, snapshot: snapshot);

    // Failed state label renders (localized "Transfer failed").
    expect(find.textContaining('Transfer failed'), findsOneWidget);
    // The error icon (Icons.error_outline) renders for the failed state.
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    // The normal file icon does NOT render alongside it.
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing);
  });

  testWidgets('DM offered download disables during the real transfer',
      (tester) async {
    final descriptor = _fileDescriptor(
      attachmentId: 'att-busy',
      fileName: 'busy.pdf',
      mime: 'application/pdf',
      totalSize: 1536,
    );
    final snapshot = _snapshot(
      sessionId: sessionId,
      displayName: 'alice',
      messages: [
        _msgWithAttachment(
          fromDevice: 'bob',
          body: 'download this',
          attachment: descriptor,
          sentAtMs: base,
        ),
      ],
      attachments: [
        _view(
          attachmentId: 'att-busy',
          direction: 'incoming',
          state: AttachmentState.offered,
        ),
      ],
    );
    final gateway = ScriptableGateway()..hold(GatewayMethod.downloadAttachment);

    await _pump(
      tester,
      sessionId: sessionId,
      snapshot: snapshot,
      gateway: gateway,
    );
    expect(tester.widget<IconButton>(_attachmentAction()).onPressed, isNotNull);

    await tester.tap(_attachmentAction());
    await tester.pump();
    expect(tester.widget<IconButton>(_attachmentAction()).onPressed, isNull);

    gateway.release(GatewayMethod.downloadAttachment);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<IconButton>(_attachmentAction()).onPressed, isNotNull);
  });

  testWidgets('available non-media attachment opens with the injected launcher',
      (tester) async {
    final descriptor = _fileDescriptor(
      attachmentId: 'att-external',
      fileName: 'report.pdf',
      mime: 'application/pdf',
      totalSize: 1536,
    );
    final launcher = RecordingAttachmentLauncher();
    await _pump(
      tester,
      sessionId: sessionId,
      launcher: launcher,
      snapshot: _snapshot(
        sessionId: sessionId,
        displayName: 'alice',
        messages: [
          _msgWithAttachment(
            fromDevice: 'alice',
            body: 'local report',
            attachment: descriptor,
            sentAtMs: base,
          ),
        ],
        attachments: [
          _view(
            attachmentId: 'att-external',
            direction: 'outgoing',
            state: AttachmentState.available,
            localPath: '/tmp/report.pdf',
          ),
        ],
      ),
    );

    await tester.tap(_attachmentAction());
    await tester.pump();

    expect(launcher.paths, ['/tmp/report.pdf']);
  });

  testWidgets('launcher failure is surfaced in a SnackBar', (tester) async {
    final descriptor = _fileDescriptor(
      attachmentId: 'att-failure',
      fileName: 'report.pdf',
      mime: 'application/pdf',
      totalSize: 1536,
    );
    await _pump(
      tester,
      sessionId: sessionId,
      launcher: RecordingAttachmentLauncher(
        error: StateError('launcher failed'),
      ),
      snapshot: _snapshot(
        sessionId: sessionId,
        displayName: 'alice',
        messages: [
          _msgWithAttachment(
            fromDevice: 'alice',
            body: 'local report',
            attachment: descriptor,
            sentAtMs: base,
          ),
        ],
        attachments: [
          _view(
            attachmentId: 'att-failure',
            direction: 'outgoing',
            state: AttachmentState.available,
            localPath: '/tmp/report.pdf',
          ),
        ],
      ),
    );

    await tester.tap(_attachmentAction());
    await tester.pump();

    expect(find.text('launcher failed'), findsOneWidget);
  });

  testWidgets('empty local path keeps available Open disabled', (tester) async {
    final descriptor = _fileDescriptor(
      attachmentId: 'att-empty',
      fileName: 'report.pdf',
      mime: 'application/pdf',
      totalSize: 1536,
    );
    await _pump(
      tester,
      sessionId: sessionId,
      snapshot: _snapshot(
        sessionId: sessionId,
        displayName: 'alice',
        messages: [
          _msgWithAttachment(
            fromDevice: 'alice',
            body: 'not local',
            attachment: descriptor,
            sentAtMs: base,
          ),
        ],
        attachments: [
          _view(
            attachmentId: 'att-empty',
            direction: 'outgoing',
            state: AttachmentState.available,
            localPath: '',
          ),
        ],
      ),
    );

    expect(tester.widget<IconButton>(_attachmentAction()).onPressed, isNull);
  });
}
