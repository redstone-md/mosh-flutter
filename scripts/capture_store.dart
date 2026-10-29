// Store screenshots of the shipping Flutter UI with fictional data, no Rust.
// flutter test scripts/capture_store.dart --dart-define=SETUP_PREVIEW=true
//
// Writes phone shots (1080 × 1920) where F-Droid and RuStore read them, and
// desktop shots (1920 × 1080) for Microsoft Store, in English and Russian.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/features/voice_call/call_modal_card.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/locale_preference_store.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';

import '../test/features/routing/shell_harness.dart';
import '../test/support/first_run_preview.dart';
import '../test/support/locale.dart';
import '../test/support/message_builders.dart';
import '../test/support/scriptable_bridge.dart';
import '../test/support/scriptable_gateway.dart';
import '../test/support/voice_call_fakes.dart';

/// One listing language: where its files go and the sample conversation.
class _Listing {
  const _Listing(this.locale, this.folder,
      {required this.me,
      required this.peer,
      required this.settings,
      required this.chat,
      required this.others});
  final Locale locale;
  final String folder;
  final String me;
  final String peer;
  final String settings;
  final List<(bool mine, String body)> chat;
  final ({
    String friend,
    String hello,
    String group,
    String plans,
    String channel,
    String post
  }) others;
}

const _listings = [
  _Listing(Locale('en'), 'en-US',
      me: 'Alex',
      peer: 'Maya Chen',
      settings: 'Sound & Video',
      chat: [
        (false, 'Coffee after the walk?'),
        (true, 'Absolutely. Riverside at 10?'),
        (false, 'Perfect. The weather looks good for once.'),
        (true, 'I found a quieter route along the river.'),
        (false, 'That looks lovely. Let\'s take the long way back.'),
        (true, 'Deal. I\'ll bring the camera.'),
        (false, 'See you by the bridge!'),
      ],
      others: (
        friend: 'Leo Park',
        hello: 'Thanks for the photos!',
        group: 'Weekend plans',
        plans: 'Saturday works for everyone.',
        channel: 'photography',
        post: 'A few frames from the coast.',
      )),
  _Listing(Locale('ru'), 'ru-RU',
      me: 'Саша',
      peer: 'Майя Чен',
      settings: 'Звук и видео',
      chat: [
        (false, 'Кофе после прогулки?'),
        (true, 'Конечно. На набережной в 10?'),
        (false, 'Отлично. Погода наконец хорошая.'),
        (true, 'Я нашёл тихий маршрут вдоль реки.'),
        (false, 'Звучит здорово. Обратно пойдём длинной дорогой.'),
        (true, 'Договорились. Возьму камеру.'),
        (false, 'Встретимся у моста!'),
      ],
      others: (
        friend: 'Лёва Пак',
        hello: 'Спасибо за фотографии!',
        group: 'Планы на выходные',
        plans: 'Суббота всем подходит.',
        channel: 'фото',
        post: 'Пара кадров с побережья.',
      )),
];

/// A form factor: logical size, export scale and output directory.
class _Device {
  const _Device(this.size, this.scale, this.directory, {this.phone = false});
  final Size size;
  final bool phone;
  final double scale;
  final String Function(String folder) directory;
}

final _phone = _Device(const Size(360, 640), 3,
    (folder) => 'fastlane/metadata/android/$folder/images/phoneScreenshots',
    phone: true);
final _desktop = _Device(const Size(1280, 720), 1.5,
    (folder) => 'fastlane/metadata/msstore/$folder/screenshots');

final _time = DateTime(2026, 10, 3, 9, 41);

ScriptableGateway _gateway(_Listing listing, {ActiveCall? call}) {
  final o = listing.others;
  return ScriptableGateway()
    ..seedSessions([
      TestSnapshots.dm(
          sessionId: 'maya',
          displayName: listing.me,
          peerDisplayName: listing.peer,
          activeCall: call,
          messages: [
            for (final (index, (mine, body)) in listing.chat.indexed)
              TestMessages.dm(
                  fromDevice: mine ? listing.me : listing.peer,
                  body: body,
                  messageId: 'walk-$index',
                  sentAtMs: BigInt.from(_time
                      .add(Duration(minutes: index))
                      .millisecondsSinceEpoch),
                  deliveryStatus: MessageDeliveryStatus.sent,
                  read: mine),
          ]),
      TestSnapshots.dm(
          sessionId: 'leo',
          peerDisplayName: o.friend,
          messages: [TestMessages.dm(fromDevice: o.friend, body: o.hello)]),
    ])
    ..seedGroups([
      TestSnapshots.group(
          groupId: 'weekend',
          label: o.group,
          deviceFingerprint: 'self',
          messages: [
            TestMessages.group(
                fromDevice: o.friend, fromFingerprint: 'leo', body: o.plans)
          ]),
    ])
    ..seedChannels([
      TestSnapshots.channel(
          name: o.channel,
          deviceFingerprint: 'self',
          messages: [
            TestMessages.channel(
                fromDevice: o.friend, fromFingerprint: 'leo', body: o.post)
          ]),
    ]);
}

/// Media state of a connected voice call, as the native owner reports it.
native.Snapshot _callMedia() => native.Snapshot(
    sessionId: 'maya',
    callId: 'walk',
    ready: true,
    microphone: true,
    microphoneRequested: true,
    microphoneAvailable: true,
    camera: false,
    cameraRequested: false,
    cameraStarting: false,
    cameraFailed: false,
    remoteCamera: false,
    reconnecting: false,
    failed: false,
    videoWidth: 0,
    videoHeight: 0,
    videoFps: 0,
    packetsDropped: BigInt.zero,
    inputs: const [],
    outputs: const [],
    cameras: const []);

Future<NativeCallOwner> _open(
    WidgetTester tester, _Listing listing, _Device device,
    {String location = AppRoutes.sessions, ActiveCall? call}) async {
  final gateway = _gateway(listing, call: call);
  final bridge = ScriptableBridge(conversations: gateway.conversations);
  // A phone hands calls to the Android owner, which shows the full-screen
  // call; desktop keeps the in-app call strip.
  final phoneCall = call != null && device.phone;
  final owner = NativeCallOwner(bridge, () async => true);
  if (phoneCall) {
    for (var i = 0; i < 20; i++) {
      bridge.respondNext(
          BridgeMethod.nativeCallSnapshot, Future.value(_callMedia()));
    }
  }
  await pumpShellApp(tester,
      gateway: gateway,
      bridge: bridge,
      physical: device.size,
      location: location,
      overrides: [
        localePreferenceStoreProvider
            .overrideWithValue(MemoryLocalePreferenceStore(listing.locale)),
        voiceCaptureFactoryProvider.overrideWithValue(RecordingCapture()),
        voicePlaybackFactoryProvider.overrideWithValue(RecordingPlayback()),
        if (phoneCall) nativeCallOwnerProvider.overrideWithValue(owner),
      ]);
  return owner;
}

Future<void> _save(
    WidgetTester tester, _Listing listing, _Device device, int index) async {
  expect(tester.takeException(), isNull);
  await tester.pump();
  final boundary = tester
      .firstRenderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: device.scale);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${device.directory(listing.folder)}/$index.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    const recorder = MethodChannel('com.llfbandit.record/messages');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recorder, (call) async => null);
  });

  for (final listing in _listings) {
    _capture(listing, 'phone', _phone);
    _capture(listing, 'desktop', _desktop);
  }
}

/// The four store screens for one language and form factor, in listing order.
void _capture(_Listing listing, String name, _Device device) {
  final tag = '${listing.folder} $name';

  testWidgets('$tag chats', (tester) async {
    await prepareSetupPreview(tester);
    await _open(tester, listing, device);
    expect(find.text(listing.others.group), findsWidgets);
    await _save(tester, listing, device, 1);
  });

  testWidgets('$tag conversation', (tester) async {
    await prepareSetupPreview(tester);
    await _open(tester, listing, device);
    await tester.tap(find
        .descendant(
            of: find.byType(SessionsScreen), matching: find.text(listing.peer))
        .first);
    await tester.pumpAndSettle();
    expect(find.text(listing.chat.last.$2), findsWidgets);
    await _save(tester, listing, device, 2);
  });

  testWidgets('$tag call', (tester) async {
    await prepareSetupPreview(tester);
    final owner = await _open(tester, listing, device,
        location: AppRoutes.dmFor('maya'),
        call: TestCalls.active(
            callId: 'walk',
            startedAtMs: BigInt.from(DateTime.now()
                .subtract(const Duration(minutes: 4, seconds: 12))
                .millisecondsSinceEpoch)));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    // Let the call surface finish expanding.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CallModalCard), findsOneWidget);
    await _save(tester, listing, device, 3);
    // The owner outlives the tree; stopping it ends media polling.
    owner.dispose();
    await tester.pump();
  });

  testWidgets('$tag settings', (tester) async {
    await prepareSetupPreview(tester);
    await _open(tester, listing, device, location: AppRoutes.settings);
    await tester.tap(find.text(listing.settings).last);
    await tester.pumpAndSettle();
    await _save(tester, listing, device, 4);
  });
}
