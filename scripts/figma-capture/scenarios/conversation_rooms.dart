// Seeded "Weekend plans" group and #photography channel threads.
part of 'conversation_fixtures.dart';

GroupMessage groupMsg(
        String id, String from, String fp, String body, BigInt sent,
        {AttachmentDescriptor? attachment,
        GroupNameChanged? rename,
        MessageDeliveryStatus? status}) =>
    GroupMessage(
        fromDevice: from,
        fromFingerprint: fp,
        body: body,
        messageId: id,
        sentAtMs: sent,
        attachment: attachment,
        nameChange: rename,
        deliveryStatus:
            fp == meFp ? (status ?? MessageDeliveryStatus.sent) : null);

List<GroupMessage> groupThread() => [
      groupMsg('g1', leo, leoFp, 'Who is in for Saturday?',
          at(daysAgo: 1, hour: 19)),
      groupMsg('g2', leo, leoFp, '', at(daysAgo: 1, hour: 19, minute: 1),
          rename: const GroupNameChanged(name: groupName)),
      groupMsg('g3', priya, priyaFp, 'Me! I can bring snacks and the big tent.',
          at(daysAgo: 1, hour: 19, minute: 4)),
      groupMsg('g4', maya, mayaFp, 'Count me in. The cabin is booked.',
          at(hour: 8, minute: 15)),
      groupMsg(
          'g5',
          maya,
          mayaFp,
          'Check-in is from 3 pm, keys are in the lockbox.',
          at(hour: 8, minute: 16)),
      groupMsg(
          'g6',
          me,
          meFp,
          'Great, I will sort out the playlist for the drive.',
          at(hour: 9, minute: 2)),
      groupMsg('g7', leo, leoFp, 'Leaving at 6 sharp. Coffee is on me.',
          at(hour: 9, minute: 20)),
    ];

GroupSnapshot groupSnapshot({
  List<GroupMessage>? messages,
  List<AttachmentView> attachments = const [],
  bool needsRejoin = false,
  bool typing = false,
  UnreadState? unread,
}) =>
    GroupSnapshot(
      unread: unread,
      groupId: groupId,
      meshId: 'mesh-coast',
      label: groupName,
      displayName: me,
      deviceFingerprint: meFp,
      creatorFingerprint: leoFp,
      isAdmin: true,
      state: 'ready',
      memberCount: BigInt.from(4),
      messages: messages ?? groupThread(),
      attachments: attachments,
      dmOffers: const [],
      mesh: TestSnapshots.mesh(meshId: 'mesh-coast', peerCount: 4),
      events: const [],
      needsRejoin: needsRejoin,
      memberPeerIds: const [meFp, leoFp, priyaFp, mayaFp],
      typingMembers: [
        if (typing)
          TypingMember(
              fingerprint: priyaFp,
              displayName: priya,
              untilMs: BigInt.from(DateTime.now()
                  .add(const Duration(hours: 2))
                  .millisecondsSinceEpoch)),
      ],
    );

ChannelMessage channelMsg(
        String id, String from, String fp, String body, BigInt sent,
        {AttachmentDescriptor? attachment}) =>
    ChannelMessage(
        fromDevice: from,
        fromFingerprint: fp,
        body: body,
        messageId: id,
        sentAtMs: sent,
        attachment: attachment,
        deliveryStatus: fp == meFp ? MessageDeliveryStatus.sent : null);

List<ChannelMessage> channelThread() => [
      channelMsg(
          'p1',
          priya,
          priyaFp,
          'Golden hour at the harbour today was unreal.',
          at(hour: 7, minute: 40)),
      channelMsg(
          'p2', leo, leoFp, 'Which lens did you use?', at(hour: 7, minute: 52)),
      channelMsg('p3', priya, priyaFp, 'The 35 mm prime, wide open at f/1.8.',
          at(hour: 7, minute: 55)),
      channelMsg(
          'p4',
          me,
          meFp,
          'The light on the water looks amazing. Any tips for long exposures?',
          at(hour: 8, minute: 10)),
      channelMsg(
          'p5',
          leo,
          leoFp,
          'ND filter and a sturdy tripod. Start around 10 seconds.',
          at(hour: 8, minute: 14)),
    ];

ChannelSnapshot channelSnapshot({
  List<ChannelMessage>? messages,
  List<AttachmentView> attachments = const [],
  HistorySync? historySync,
}) =>
    ChannelSnapshot(
      historySync: historySync,
      name: channelName,
      topic: 'Share your favourite frames',
      meshId: 'mesh-coast',
      displayName: me,
      deviceFingerprint: meFp,
      messages: messages ?? channelThread(),
      attachments: attachments,
      dmOffers: const [],
      mesh: TestSnapshots.mesh(meshId: 'mesh-coast', peerCount: 6),
      events: const [],
    );
