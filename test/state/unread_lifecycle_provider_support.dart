part of 'unread_lifecycle_provider_test.dart';

/// A recording fake of the notifications plugin: `show` records every call
/// (id, title, body) so a test can assert the toast gate fired + the body
/// text. `noSuchMethod` covers the rest so any unmocked call surfaces
/// loudly (the notifications-provider-test convention).
class _RecordingNotifications implements FlutterLocalNotificationsPlugin {
  final List<
      ({
        int id,
        String? title,
        String? body,
        String? payload,
        NotificationDetails? details,
      })> shows = [];

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    shows.add((
      id: id,
      title: title,
      body: body,
      payload: payload,
      details: notificationDetails,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(' ${invocation.memberName}');
}

/// The fixtures carry the unread count the core reports; their messages
/// play no part in it.
SessionSnapshot _dmSession({required String sessionId, int unread = 0}) =>
    SessionSnapshot(
      inviteAvailable: false,
      sessionId: sessionId,
      meshId: 'm',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: '',
      state: DmSessionState.connected,
      transport: PeerTransport.direct,
      inviteUri: null,
      fingerprint: 'fp',
      messages: const [],
      unread: UnreadState(count: unread),
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

ChannelSnapshot _channel({required String name, int unread = 0}) =>
    ChannelSnapshot(
      name: name,
      topic: '',
      meshId: 'm',
      displayName: 'me',
      deviceFingerprint: 'ownfp',
      messages: const [],
      unread: UnreadState(count: unread),
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
    );

GroupSnapshot _group({required String groupId, int unread = 0}) =>
    GroupSnapshot(
      groupId: groupId,
      meshId: 'm',
      label: null,
      displayName: 'me',
      deviceFingerprint: 'ownfp',
      creatorFingerprint: 'ownfp',
      isAdmin: false,
      state: 'ready',
      memberCount: BigInt.two,
      messages: const [],
      unread: UnreadState(count: unread),
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      memberPeerIds: const [],
      typingMembers: const [],
    );

/// Harness wiring the four overrides + a controllable focus flag. Each
/// test builds its own harness for isolation. The generative constructor
/// is named `_internal` so the unnamed `factory` can build it (Dart
/// allows only one unnamed constructor per class).
class _Harness {
  final ProviderContainer container;
  final ScriptableBridge gateway;
  final _RecordingNotifications notifications;
  final void Function(bool focused) setFocus;

  _Harness._internal(
      this.container, this.gateway, this.notifications, this.setFocus);

  factory _Harness(
      {bool notificationsReady = true, AndroidAppAccess? appAccess}) {
    final gateway = ScriptableBridge();
    final notifications = _RecordingNotifications();
    // The focus flag is mutable; the seam closure reads it each call so a
    // test can flip focus between polls.
    var focused = true;
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(gateway),
      if (appAccess != null)
        androidAppAccessProvider.overrideWithValue(appAccess),
      windowFocusProvider.overrideWithValue(() async => focused),
      flutterLocalNotificationsPluginProvider.overrideWithValue(notifications),
      notificationsReadyProvider
          .overrideWithValue(AsyncValue.data(notificationsReady)),
    ]);
    return _Harness._internal(
      container,
      gateway,
      notifications,
      (value) => focused = value,
    );
  }
}

/// Drives one poll: refreshes the three list providers (so the count
/// providers recompute from the gateway's current snapshots), awaits
/// their resolution, then forces the lifecycle to rebuild + pumps
/// microtasks so its async `_runDiff` (focus check + toast awaits) settles
/// before assertions.
Future<void> _poll(ProviderContainer container) async {
  await refreshConversationLists(container.read);
  // Resolve the count providers so the lifecycle's `build` re-run sees data.
  for (final kind in ConversationKind.values) {
    await container.read(unreadCountsProvider(kind).future);
  }
  // Reading the lifecycle forces its `build` to re-run (the count providers
  // changed, so it is dirty); the build fires the async `_runDiff`. Pump
  // microtasks so the focus closure + optional plugin.show awaits resolve
  // and `state` is updated before the caller asserts.
  container.read(unreadLifecycleProvider);
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
