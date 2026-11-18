import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/wake/wake_client.dart';
import 'package:mosh/src/features/wake/wake_registration.dart';
import 'package:mosh/src/features/wake/wake_sender.dart';
import 'package:mosh/src/rust/private_dm_runtime/wake.dart';

import 'wake_service_stub.dart';

class _Device implements WakeDevice {
  WakeTokens? current;
  String? stored;

  @override
  Future<WakeTokens?> tokens() async => current;
  @override
  Future<String?> loadRegistration() async => stored;
  @override
  Future<void> saveRegistration(String registration) async =>
      stored = registration;
}

void main() {
  late WakeServiceStub service;
  late WakeClient client;
  late _Device device;
  late List<(String, String)> announced;
  late WakeRegistrar registrar;
  const first = WakeTokens(voip: 'aa', apns: 'bb', environment: 'production');

  setUp(() async {
    service = await WakeServiceStub.start();
    client = WakeClient();
    device = _Device()..current = first;
    announced = [];
    registrar = WakeRegistrar(
        service: service.uri,
        device: device,
        client: client,
        announce: (url, handle) async => announced.add((url, handle)));
    addTearDown(() async {
      client.close();
      await service.close();
    });
  });

  List<String> calls() =>
      [for (final (method, path, _, _) in service.requests) '$method $path'];

  test('a phone registers once and announces the same handle every launch',
      () async {
    service.statuses.add(201);

    await registrar.run();
    await registrar.run();

    expect(calls(), ['POST /v1/devices']);
    expect(announced, [
      (service.uri.toString(), 'h'),
      (service.uri.toString(), 'h'),
    ]);
  });

  // The launch run and the token callback can overlap on a first launch.
  test('overlapping runs register one handle', () async {
    service.statuses.add(201);

    await Future.wait([registrar.run(), registrar.run()]);

    expect(calls(), ['POST /v1/devices']);
    expect(announced.map((a) => a.$2), ['h', 'h']);
  });

  test('new tokens update the entry and keep the handle', () async {
    service.statuses.addAll([201, 204]);
    await registrar.run();

    device.current =
        const WakeTokens(voip: 'cc', apns: 'bb', environment: 'production');
    await registrar.run();

    expect(calls(), ['POST /v1/devices', 'PUT /v1/devices/h']);
    expect(announced.last.$2, 'h');
  });

  test('an entry the service lost is registered anew under a new handle',
      () async {
    service.statuses.addAll([201, 401, 201]);
    await registrar.run();
    service.created = {'handle': 'h2', 'secret': 's2'};

    device.current = const WakeTokens(voip: 'cc', environment: 'production');
    await registrar.run();

    expect(
        calls(), ['POST /v1/devices', 'PUT /v1/devices/h', 'POST /v1/devices']);
    expect(announced.last.$2, 'h2');
  });

  test('a phone without tokens yet registers nothing', () async {
    device.current = null;

    expect(await registrar.run(), isFalse);
    expect(service.requests, isEmpty);
    expect(announced, isEmpty);
  });

  test('a sender drops a handle the service no longer knows for calls',
      () async {
    service.statuses.addAll([404, 404, 202]);
    final forgotten = <String>[];
    WakeRequest wake(String handle, {String? call}) => WakeRequest(
        service: service.uri.toString(), handle: handle, callId: call);
    final sender = WakeSender(
        // A phone without an alert token answers 404 to texts only.
        take: () async => [
              wake('no-alerts'),
              wake('gone', call: 'c'),
              wake('here', call: 'd')
            ],
        forget: (handle) async => forgotten.add(handle),
        client: client);

    await sender.send();

    expect(forgotten, ['gone']);
  });

  test('a sender tries a refused wake again on its next round', () async {
    service.statuses.addAll([502, 202]);
    final wake =
        WakeRequest(service: service.uri.toString(), handle: 'h', callId: 'c');
    var waiting = [wake];
    final sender = WakeSender(
        take: () async {
          final due = waiting;
          waiting = [];
          return due;
        },
        forget: (_) async {},
        client: client);

    await sender.send();
    await sender.send();

    expect(calls(), ['POST /v1/wake', 'POST /v1/wake']);
  });
}
