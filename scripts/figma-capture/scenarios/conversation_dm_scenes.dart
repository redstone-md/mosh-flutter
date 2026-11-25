// DM scenes, including the media viewer opened from a DM.
part of 'conversation_test.dart';

final _dmScenes = <FigmaScene>[
  scene('dm-empty', 'Conversation / DM / Empty', (tester, size) async {
    await _dm(tester, size, dmSession(messages: const []));
  }),
  scene('dm-loading', 'Conversation / DM / Loading', (tester, size) async {
    await openShellUnsettled(tester, size,
        gateway: seededGateway(),
        location: AppRoutes.dmFor(dmId),
        overrides: [
          activeSessionProvider(dmId)
              .overrideWith((ref) => Completer<SessionSnapshot>().future),
        ]);
  }),
  scene('dm-load-error', 'Conversation / DM / Load error',
      (tester, size) async {
    await openShell(tester, size, gateway: seededGateway(), overrides: [
      activeSessionProvider(dmId).overrideWith((ref) async =>
          throw Exception('This conversation could not be read from disk.')),
    ]);
  }),
  scene('dm-thread', 'Conversation / DM / Thread', (tester, size) async {
    await _dm(
        tester,
        size,
        dmSession(
            unread: const UnreadState(count: 2, firstUnreadMessageId: 'd5')));
  }),
  scene('dm-typing', 'Conversation / DM / Typing and draft',
      (tester, size) async {
    await _dm(tester, size, dmSession(typing: true));
    await _closeDocked(tester, size);
    await tester.enterText(_composerField, 'Yes, I have two. Packing them now');
    await _settle(tester);
  }),
  scene('dm-over-limit', 'Conversation / DM / Draft over the limit',
      (tester, size) async {
    await _dm(tester, size, dmSession(),
        overrides: [maxTextCharsProvider.overrideWithValue(160)]);
    await _closeDocked(tester, size);
    await tester.enterText(
        _composerField,
        'Packing list so far: two headlamps, the big tent, sleeping bags, '
        'the camping stove, a gas canister, coffee, the thermos, rain jackets '
        'and the first aid kit. Anything else we need?');
    await _settle(tester);
  }),
  scene('dm-attachments', 'Conversation / DM / Attachments',
      (tester, size) async {
    await _attachments(tester, size);
  }),
  scene('dm-voice', 'Conversation / DM / Voice messages', (tester, size) async {
    final data = dmVoice();
    // The note that is still arriving spins, so the scene never settles.
    await openShellUnsettled(tester, size,
        gateway: seededGateway(
            dm: dmSession(
                messages: data.messages, attachments: data.transfers)),
        location: AppRoutes.dmFor(dmId));
  }),
  scene('dm-calls', 'Conversation / DM / Call log', (tester, size) async {
    await _dm(tester, size, dmSession(messages: dmCalls()));
  }),
  scene('dm-voice-recording', 'Conversation / DM / Voice recording',
      (tester, size) async {
    await _record(tester, size);
  }),
  scene('dm-voice-review', 'Conversation / DM / Voice recorded',
      (tester, size) async {
    await _record(tester, size);
    await tester.tap(find.byTooltip(l10n.voiceStopLabel));
    await _settle(tester);
  }),
  scene('dm-connecting', 'Conversation / DM / Peer offline',
      (tester, size) async {
    await _dm(
        tester,
        size,
        dmSession(
            state: DmSessionState.handshaking, transport: PeerTransport.none));
  }),
  scene('dm-invite', 'Conversation / DM / Invite waiting, menu',
      (tester, size) async {
    await openShell(tester, size,
        gateway: seededGateway(extraSessions: [
          fakeSession(
              sessionId: 'invite',
              displayName: me,
              role: 'inviter',
              inviteUri: 'mosh://invite?session=invite&mesh=mesh-coast',
              fingerprint: '9f3a61c2e07b5d48',
              inviteAvailable: true),
        ]),
        location: AppRoutes.dmFor('invite'));
    await _menu(tester);
  }),
  scene('dm-send-failed', 'Conversation / DM / Send failed banner',
      (tester, size) async {
    final gateway = seededGateway()
      ..failNext(GatewayMethod.send,
          error: Exception('Maya Chen is not reachable right now'));
    await openShell(tester, size, gateway: gateway);
    await tester.enterText(_composerField, 'See you at 6!');
    await tester.tap(find.byKey(kComposerSendButtonKey));
    await _settle(tester);
  }),
  scene('dm-chat-error', 'Conversation / DM / Error banner',
      (tester, size) async {
    await _dm(tester, size, dmSession());
    ProviderScope.containerOf(tester.element(find.byType(DmScreen)))
        .read(conversationControllerProvider(const DmTarget(dmId)).notifier)
        .showError('Maya Chen is already in another call.');
    await _settle(tester);
  }),
  scene('dm-removal-pending', 'Conversation / DM / Device removal pending',
      (tester, size) async {
    await _dm(
        tester, size, dmSession(revocation: DmDeviceRevocationState.pending));
  }),
  scene('dm-revoked', 'Conversation / DM / Device revoked',
      (tester, size) async {
    await _dm(
        tester, size, dmSession(revocation: DmDeviceRevocationState.revoked));
  }),
  scene('dm-history-waiting', 'Conversation / DM / History waiting',
      (tester, size) async {
    await _dm(
        tester,
        size,
        dmSession(
            messages: const [],
            historySync: DmHistorySyncState.waitingForSource));
  }),
  scene('dm-history-importing', 'Conversation / DM / History importing',
      (tester, size) async {
    await _dm(
        tester, size, dmSession(historySync: DmHistorySyncState.importing));
  }),
  scene('dm-deleted', 'Conversation / DM / Deleted messages',
      (tester, size) async {
    await _dm(
        tester,
        size,
        dmSession(
            messages: dmThreadWithDeletions(),
            deletion: DeletionSummary(
                pendingCount: BigInt.one, rejectedCount: BigInt.one)));
  }),
  scene('dm-header-menu', 'Conversation / DM / Header menu',
      (tester, size) async {
    await _dm(tester, size, dmSession(), overrides: [
      personalChatRenameAvailableProvider.overrideWithValue(true)
    ]);
    await _menu(tester);
  }),
  scene('dm-rename', 'Conversation / DM / Rename dialog', (tester, size) async {
    await _dm(tester, size, dmSession(), overrides: [
      personalChatRenameAvailableProvider.overrideWithValue(true)
    ]);
    await _menu(tester, l10n.chatRename);
  }),
  scene('dm-delete', 'Conversation / DM / Delete chat confirm',
      (tester, size) async {
    await _dm(tester, size, dmSession());
    await _menu(tester, l10n.deleteChatConfirm);
  }),
  scene('dm-context-menu', 'Conversation / DM / Message context menu',
      (tester, size) async {
    await _dm(tester, size, dmSession());
    await openMessageMenu(
        tester, 'I booked the cabin near the lighthouse for two nights.');
  }),
  scene('dm-delete-message', 'Conversation / DM / Delete message dialog',
      (tester, size) async {
    await _dm(tester, size, dmSession());
    await openMessageMenu(tester, 'Should we leave at 6 to beat the traffic?');
    await tester.tap(find.text('Delete…'));
    await _settle(tester);
  }),
  scene('dm-file-menu', 'Conversation / DM / File context menu',
      (tester, size) async {
    await _attachments(tester, size);
    await tester.scrollUntilVisible(inThread('trail-map.zip'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ConversationMessageListView),
                matching: find.byType(Scrollable))
            .first);
    await tester.ensureVisible(inThread('trail-map.zip').first);
    await _settle(tester);
    await openMessageMenu(tester, 'trail-map.zip');
  }),
  scene('dm-selection', 'Conversation / DM / Message selection',
      (tester, size) async {
    await _dm(tester, size, dmSession());
    await startMessageSelection(
        tester, 'Should we leave at 6 to beat the traffic?');
    await tester.tap(find.text('Sending the packing list in a minute.'));
    await _settle(tester);
    await tester.tap(
        find.text('I booked the cabin near the lighthouse for two nights.'));
    await _settle(tester);
  }),
  scene('dm-search', 'Conversation / DM / Search', (tester, size) async {
    await _dm(tester, size, dmSession());
    await _search(tester, 'cabin');
  }),
  scene('dm-search-empty', 'Conversation / DM / Search, no results',
      (tester, size) async {
    await _dm(tester, size, dmSession());
    await _search(tester, 'kayak');
  }),
  scene('dm-files-filter', 'Conversation / DM / Files filter',
      (tester, size) async {
    await _attachments(tester, size);
    await _menu(tester, l10n.chatFilterAttachments);
  }),
  scene('dm-details', 'Conversation / DM / Details', (tester, size) async {
    await _attachments(tester, size);
    await _menu(tester, l10n.chatDetailsTitle);
  }, devices: _mobileOnly),
  scene('dm-connection', 'Conversation / DM / Details, connection expanded',
      (tester, size) async {
    await _dm(tester, size, dmSession());
    if (!isDesktop(size)) await _menu(tester, l10n.chatDetailsTitle);
    final diagnostics = find.text(l10n.chatDetailsDiagnostics);
    await tester.ensureVisible(diagnostics);
    await tester.tap(diagnostics);
    await _settle(tester);
  }),
  scene('dm-peer-status', 'Conversation / DM / Peer status drawer',
      (tester, size) async {
    await _dm(tester, size, dmSession());
    await tester.tap(find.descendant(
        of: find.byType(MoshTitleBar), matching: find.text('Connected')));
    await _settle(tester);
  }, devices: _desktopOnly),
  scene('dm-drop', 'Conversation / DM / Drop a file', (tester, size) async {
    await _dm(tester, size, dmSession());
    await _closeDocked(tester, size);
    const codec = StandardMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'desktop_drop',
        codec.encodeMethodCall(const MethodCall('entered', [700.0, 400.0])),
        (_) {});
    await _settle(tester);
  }, devices: _desktopOnly),
  scene('media-viewer', 'Conversation / Media viewer / Image',
      (tester, size) async {
    await _attachments(tester, size, onDisk: true);
    // The picture in the feed, not its row in the shared files.
    await tester.tap(find.descendant(
        of: find.byType(ConversationMessageListView),
        matching: find.byWidgetPredicate((w) =>
            w is Semantics && w.properties.label == 'Open harbour.jpg')));
    await _settle(tester);
  }),
  scene('viewer-video', 'Conversation / Media viewer / Video unavailable',
      (tester, size) async {
    await _viewer(tester, size, file('a3', 'waves.mp4', 'video/mp4', 18400000),
        () => throw UnsupportedError('no player'));
  }),
  scene('viewer-audio', 'Conversation / Media viewer / Audio',
      (tester, size) async {
    await _viewer(
        tester,
        size,
        file('au', 'harbour-ambience.mp3', 'audio/mpeg', 3400000),
        () => Player(platformPlayer: _ClipPlayback()));
  }),
  scene('viewer-file', 'Conversation / Media viewer / Unsupported file',
      (tester, size) async {
    await _viewer(
        tester,
        size,
        file('a4', 'coast-route.pdf', 'application/pdf', 1260000),
        () => throw UnsupportedError('no player'));
  }),
];
