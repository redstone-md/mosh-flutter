// Widget tests for the in-scope attachment card rendered inside a GROUP
// message bubble (lib/src/features/dm/attachment_card.dart, wired into the
// group row by lib/src/features/group/group_message_row.dart +
// group_screen.dart). Render-only stage: the transfer callbacks are no-op
// stubs (the group attachment-transfer Gateway seam is a later atomic),
// mirroring the DM display-only stage (`b7660f8`) and its test
// (dm_screen_attachment_test.dart). We seed a peer message carrying a file
// descriptor + a matching offered AttachmentView and assert the card
// renders the file name + offered state label -- proving the per-message
// AttachmentView lookup (snapshot.attachments by attachmentId) wires the
// view into the row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/group/group_screen.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/channel_group_providers.dart';

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

GroupMessage _msgWithAttachment({
  required String fromDevice,
  required String fromFingerprint,
  required String body,
  required AttachmentDescriptor attachment,
  BigInt? sentAtMs,
}) =>
    GroupMessage(
      fromDevice: fromDevice,
      fromFingerprint: fromFingerprint,
      body: body,
      messageId: null,
      sentAtMs: sentAtMs,
      attachment: attachment,
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
}) =>
    AttachmentView(
      attachmentId: attachmentId,
      direction: direction,
      state: state,
      completedChunks: BigInt.from(completed),
      chunkCount: BigInt.from(total),
      localPath: null,
    );

GroupSnapshot _snapshot({
  required String groupId,
  required String deviceFingerprint,
  required List<GroupMessage> messages,
  List<AttachmentView> attachments = const [],
}) =>
    GroupSnapshot(
      groupId: groupId,
      meshId: 'testmesh',
      label: null,
      displayName: 'me',
      deviceFingerprint: deviceFingerprint,
      creatorFingerprint: deviceFingerprint,
      isAdmin: true,
      state: 'ready',
      memberCount: BigInt.from(2),
      inviteUri: null,
      messages: messages,
      attachments: attachments,
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      orgPubkey: null,
      memberPeerIds: const [],
    );

Future<void> _pump(
  WidgetTester tester, {
  required String groupId,
  required GroupSnapshot snapshot,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      groupSnapshotProvider(groupId).overrideWith((ref) async => snapshot),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupScreen(groupId: groupId),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const groupId = 'group-attach';
  final base = BigInt.from(1700000000000); // 2023-11-14T22:13:20Z

  // Render-only stage: a peer message carries `report.pdf` and the
  // snapshot's attachment list carries the matching offered view. The row
  // must look the view up by attachmentId and render the AttachmentCard
  // (file name + offered state label). The transfer buttons are present
  // but wired to no-op stubs (tapping them is not asserted here -- that is
  // the later transfer-seam atomic).
  testWidgets(
      'offered peer group attachment renders the AttachmentCard file name',
      (tester) async {
    final descriptor = _fileDescriptor(
      attachmentId: 'att-1',
      fileName: 'report.pdf',
      mime: 'application/pdf',
      totalSize: 1536,
    );
    final msg = _msgWithAttachment(
      fromDevice: 'bob',
      fromFingerprint: 'fp-bob',
      body: 'here is the report',
      attachment: descriptor,
      sentAtMs: base,
    );
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      messages: [msg],
      attachments: [
        _view(
            attachmentId: 'att-1',
            direction: 'incoming',
            state: AttachmentState.offered),
      ],
    );

    await _pump(tester, groupId: groupId, snapshot: snapshot);

    // The message body still renders.
    expect(find.text('here is the report'), findsOneWidget);
    // The AttachmentCard renders the file name (data, not localized).
    expect(find.text('report.pdf'), findsOneWidget);
    // The offered state label renders (localized "Ready to download").
    expect(find.textContaining('Ready to download'), findsOneWidget);
  });

  // Regression: a peer message with an attachment but NO matching view in
  // the snapshot's list must still render the card (view: null -> the row
  // derives `offered` for a non-own peer message, React's `view?.state ??
  // (outgoing ? "available" : "offered")`). Pins that the lookup's null
  // fallback path renders the card rather than crashing.
  testWidgets(
      'peer group attachment with no matching view still renders the card',
      (tester) async {
    final descriptor = _fileDescriptor(
      attachmentId: 'att-2',
      fileName: 'photo.jpg',
      mime: 'image/jpeg',
      totalSize: 4096,
    );
    final msg = _msgWithAttachment(
      fromDevice: 'bob',
      fromFingerprint: 'fp-bob',
      body: 'no view yet',
      attachment: descriptor,
      sentAtMs: base,
    );
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      messages: [msg],
      attachments: const [],
    );

    await _pump(tester, groupId: groupId, snapshot: snapshot);

    expect(find.text('no view yet'), findsOneWidget);
    // Card renders with the file name even though no view matched.
    expect(find.text('photo.jpg'), findsOneWidget);
  });
}
