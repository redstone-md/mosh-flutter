// Group and channel scenes.
part of 'conversation_test.dart';

final _roomScenes = <FigmaScene>[
  scene('group-empty', 'Conversation / Group / Empty', (tester, size) async {
    await openShell(tester, size,
        gateway: seededGateway(group: groupSnapshot(messages: const [])),
        location: _group);
  }),
  scene('group-thread', 'Conversation / Group / Thread', (tester, size) async {
    await openShell(tester, size,
        gateway: seededGateway(
            group: groupSnapshot(
                unread:
                    const UnreadState(count: 3, firstUnreadMessageId: 'g4'))),
        location: _group);
  }),
  scene('group-typing', 'Conversation / Group / Typing', (tester, size) async {
    await openShell(tester, size,
        gateway: seededGateway(group: groupSnapshot(typing: true)),
        location: _group);
    await _closeDocked(tester, size);
  }),
  scene('group-rejoin', 'Conversation / Group / Rejoin needed',
      (tester, size) async {
    await openShell(tester, size,
        gateway: seededGateway(group: groupSnapshot(needsRejoin: true)),
        location: _group);
  }),
  scene('group-org-missing', 'Conversation / Group / Add missing org members',
      (tester, size) async {
    await openShell(tester, size,
        gateway: seededGateway(),
        location: _group,
        overrides: [
          orgAddPromptProvider(groupId).overrideWith((ref) =>
              const OrgAddPrompt(
                  count: 3,
                  busy: false,
                  missingPeerIds: ['p1', 'p2', 'p3'],
                  orgPubkey: 'org-coast')),
        ]);
  }),
  scene('group-peer', 'Conversation / Group / Message a member',
      (tester, size) async {
    await openShell(tester, size, gateway: seededGateway(), location: _group);
    await tester.tap(find.text(priya).first);
    await _settle(tester);
  }),
  scene('group-header-menu', 'Conversation / Group / Header menu',
      (tester, size) async {
    await openShell(tester, size, gateway: seededGateway(), location: _group);
    await _menu(tester);
  }),
  scene('group-rename', 'Conversation / Group / Rename dialog',
      (tester, size) async {
    await openShell(tester, size, gateway: seededGateway(), location: _group);
    await _menu(tester, l10n.chatRename);
  }),
  scene('group-leave', 'Conversation / Group / Leave confirm',
      (tester, size) async {
    await openShell(tester, size, gateway: seededGateway(), location: _group);
    await _menu(tester, l10n.groupLeaveLabel);
  }),
  scene('group-details', 'Conversation / Group / Details',
      (tester, size) async {
    await openShell(tester, size, gateway: seededGateway(), location: _group);
    await _menu(tester, l10n.chatDetailsTitle);
  }, devices: _mobileOnly),
  // Channel
  scene('channel-empty', 'Conversation / Channel / Empty',
      (tester, size) async {
    await openShell(tester, size,
        gateway: seededGateway(channel: channelSnapshot(messages: const [])),
        location: _channel);
  }),
  scene('channel-thread', 'Conversation / Channel / Thread',
      (tester, size) async {
    await openShell(tester, size, gateway: seededGateway(), location: _channel);
  }),
  scene('channel-history', 'Conversation / Channel / History importing',
      (tester, size) async {
    await openShell(tester, size,
        gateway: seededGateway(
            channel: channelSnapshot(
                historySync:
                    const HistorySync(state: HistorySyncState.importing))),
        location: _channel);
  }),
  scene('channel-leave', 'Conversation / Channel / Leave confirm',
      (tester, size) async {
    await openShell(tester, size, gateway: seededGateway(), location: _channel);
    await _menu(tester, l10n.channelLeaveLabel);
  }),
  scene('channel-details', 'Conversation / Channel / Details',
      (tester, size) async {
    await openShell(tester, size, gateway: seededGateway(), location: _channel);
    await _menu(tester, l10n.chatDetailsTitle);
  }, devices: _mobileOnly),
];
