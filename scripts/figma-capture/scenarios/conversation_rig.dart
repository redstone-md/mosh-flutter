// Test-side plumbing for conversation scenes: image settling, a fake
// recorder and an unsettled shell mount.
part of 'conversation_fixtures.dart';

/// Finishes every image decode before the exporter precaches them. A decode
/// started on the test clock resumes only when that clock pumps, so this
/// alternates a short wait on the real clock with a frame.
Future<void> settleImages(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    var pending = false;
    for (final element in find.byType(Image).evaluate()) {
      final image = (element.widget as Image).image;
      await tester.runAsync(() => precacheImage(image, element).timeout(
          const Duration(milliseconds: 200),
          onTimeout: () => pending = true));
    }
    if (!pending) return;
    await tester.pump(const Duration(milliseconds: 16));
  }
  debugPrint('images still decoding after 40 attempts');
}

/// Stands in for the record plugin: grants the microphone, writes a small
/// file on start, and answers the per-recorder state stream.
void fakeRecorder(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  const record = MethodChannel('com.llfbandit.record/messages');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final cache = Directory.systemTemp.createTempSync('mosh-figma-voice');
  var recording = false;
  String? path;
  messenger.setMockMethodCallHandler(paths, (call) async => cache.path);
  messenger.setMockMethodCallHandler(record, (call) async {
    final args = call.arguments is Map ? call.arguments as Map : const {};
    switch (call.method) {
      case 'create':
        final id = args['recorderId'];
        for (final name in ['events', 'eventsRecord']) {
          final channel = EventChannel('com.llfbandit.record/$name/$id');
          messenger.setMockStreamHandler(
              channel, MockStreamHandler.inline(onListen: (_, __) {}));
          addTearDown(() => messenger.setMockStreamHandler(channel, null));
        }
        return null;
      case 'hasPermission' || 'isEncoderSupported':
        return true;
      case 'start':
        path = args['path'] as String;
        File(path!).writeAsBytesSync([1, 2, 3]);
        recording = true;
        return null;
      case 'stop':
        recording = false;
        return path;
      case 'isRecording':
        return recording;
      case 'getAmplitude':
        return {'current': -18.0, 'max': -6.0};
      default:
        return null;
    }
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(paths, null);
    cache.deleteSync(recursive: true);
  });
}

/// The real shell without settling, for a conversation whose read never
/// lands: the loading spinner animates forever. Mirrors pumpShellApp.
Future<void> openShellUnsettled(WidgetTester tester, Size size,
    {required ScriptableGateway gateway,
    required String location,
    List<Override> overrides = const []}) async {
  appRouter.go(location);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gatewayProvider.overrideWithValue(gateway),
      ...settingsAudioOverrides(),
      bridgeFacadeProvider.overrideWithValue(
          ScriptableBridge(conversations: gateway.conversations)),
      ...figmaLocale,
      figmaCalls,
      ...overrides,
    ],
    child: const MoshApp(),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
