import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'support/linked_dm_fixture.dart';

const _appId = 'app.mosh.mosh.linked_dm_test';

/// Run with a USB-connected physical arm64 phone, or --host to verify fixtures.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError(
        'Usage: dart run scripts/android_linked_dm.dart <adb-serial|--host>');
  }
  final host = arguments.single == '--host';
  final serial = arguments.single;
  if (!host) await checkDevice(serial);
  await run('cargo', ['build', '--manifest-path', 'mosh-core/Cargo.toml']);
  final worker = await buildWorker();
  LinkedDmFixture? fixture;
  Directory? desktopDir;
  HttpServer? server;
  Future<void>? serving;
  var reversed = false;
  var failed = false;
  try {
    fixture = await LinkedDmFixture.start(worker);
    desktopDir =
        await Directory.systemTemp.createTemp('mosh-dm-android-driver-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final token = List.generate(32, (_) => Random.secure().nextInt(256))
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    serving = serve(server, fixture, token, host ? null : serial);
    if (!host) {
      await adb(
          serial, ['reverse', 'tcp:${server.port}', 'tcp:${server.port}']);
      reversed = true;
    }
    final target = host
        ? 'native_test/android_linked_dm_test.dart'
        : 'integration_test/android_linked_dm_test.dart';
    final flags = [
      'test',
      '--no-pub',
      target,
      '--dart-define=MOSH_TEST_CONTROL_URL=http://127.0.0.1:${server.port}',
      '--dart-define=MOSH_TEST_CONTROL_TOKEN=$token',
      if (host) '--dart-define=MOSH_TEST_DESKTOP_DIR=${desktopDir.path}',
      if (!host) ...['-d', serial, '--no-uninstall'],
    ];
    stdout.writeln(
        'Phase 1: confirmed pairing, history and independent messaging.');
    await run('flutter', flags, isolatedAndroid: !host);
    if (!host) await adb(serial, ['shell', 'am', 'force-stop', _appId]);
    await fixture.beforeColdStart();
    stdout.writeln('Phase 2: cold-start identity, missed text and revocation.');
    await run('flutter', flags, isolatedAndroid: !host);
    stdout.writeln(host
        ? 'Host scenario passed. Physical Android is still unverified.'
        : 'Physical Android arm64 linked DM scenario passed.');
  } catch (_) {
    failed = true;
    rethrow;
  } finally {
    await Future.wait<void>([
      if (reversed)
        adb(serial, ['reverse', '--remove', 'tcp:${server!.port}'])
            .then((_) {}),
      if (server != null) server.close(force: true).then((_) => serving),
      if (fixture != null) fixture.close(),
      if (desktopDir != null) desktopDir.delete(recursive: true).then((_) {}),
    ]).catchError((Object error, StackTrace stack) {
      // Attempt every release without replacing the scenario's failure.
      if (!failed) Error.throwWithStackTrace(error, stack);
      return <void>[];
    });
  }
}

/// Cargo identifies the current worker, including when stale binaries coexist.
Future<String> buildWorker() async {
  final result = await Process.run('cargo', [
    'test',
    '--manifest-path',
    'mosh-core/Cargo.toml',
    '--test',
    'device_link_flow',
    '--no-run',
    '--message-format=json',
  ]);
  if (result.exitCode != 0) {
    throw StateError('Native worker build failed: ${result.stderr}');
  }
  final artifacts = const LineSplitter()
      .convert(result.stdout as String)
      .map((line) => jsonDecode(line) as Json);
  final worker = artifacts.singleWhere((message) =>
      message['reason'] == 'compiler-artifact' &&
      (message['target'] as Json)['name'] == 'device_link_flow' &&
      message['executable'] is String);
  return worker['executable'] as String;
}

Future<void> checkDevice(String serial) async {
  final abi = await adb(serial, ['shell', 'getprop', 'ro.product.cpu.abi']);
  final emulator = await adb(serial, ['shell', 'getprop', 'ro.kernel.qemu']);
  if (abi.trim() != 'arm64-v8a' || emulator.trim() == '1') {
    throw StateError(
        'This acceptance scenario requires physical Android arm64');
  }
  final existing =
      await adb(serial, ['shell', 'pm', 'list', 'packages', _appId]);
  if (const LineSplitter()
      .convert(existing)
      .any((line) => line.trim() == 'package:$_appId')) {
    throw StateError(
        'A previous test installation exists. Remove $_appId before a new run.');
  }
}

Future<String> adb(String serial, List<String> arguments) async {
  final result = await Process.run('adb', ['-s', serial, ...arguments]);
  if (result.exitCode != 0) throw StateError('adb failed: ${result.stderr}');
  return result.stdout as String;
}

Future<void> run(String command, List<String> arguments,
    {bool isolatedAndroid = false}) async {
  final process = await Process.start(command, arguments,
      mode: ProcessStartMode.inheritStdio,
      environment: isolatedAndroid
          ? {'ORG_GRADLE_PROJECT_moshLinkedDmTest': 'true'}
          : null,
      runInShell: Platform.isWindows);
  if (await process.exitCode != 0) throw StateError('$command failed');
}

Future<void> serve(HttpServer server, LinkedDmFixture fixture, String token,
    String? serial) async {
  await for (final request in server) {
    try {
      if (request.method != 'POST' ||
          request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer $token') {
        request.response.statusCode = HttpStatus.forbidden;
      } else {
        final data =
            jsonDecode(await utf8.decoder.bind(request).join()) as Json;
        final action = request.uri.path.substring(1);
        final result = action == 'background'
            ? await background(serial, fixture)
            : await fixture.handle(action, data);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
      }
    } catch (_) {
      // Never print request data: QR links contain one-time pairing secrets.
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('The real fixture operation failed');
    } finally {
      await request.response.close();
    }
  }
}

Future<Json> background(String? serial, LinkedDmFixture fixture) async {
  if (serial != null) {
    await adb(serial, ['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
  }
  try {
    await Future<void>.delayed(const Duration(seconds: 2));
    await fixture.contact.stop();
    await fixture.contact.restart();
  } finally {
    if (serial != null) {
      await adb(serial,
          ['shell', 'am', 'start', '-n', '$_appId/app.mosh.mosh.MainActivity']);
    }
  }
  await waitFor(
      () => fixture.contact
          .ask({'action': 'dm_poll', 'argument': fixture.session}),
      (s) => s['state'] == 'connected',
      'The contact must reconnect after foreground return');
  await fixture.contact.ask({
    'action': 'dm_send',
    'argument': fixture.session,
    'body': 'After Android reconnect'
  });
  return {};
}
