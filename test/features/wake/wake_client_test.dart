import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/wake/wake_client.dart';
import 'package:mosh/src/rust/conversation/wake.dart';

import 'wake_service_stub.dart';

void main() {
  late WakeServiceStub service;
  late WakeClient client;
  const tokens =
      AppleWakeTokens(voip: 'aa', apns: 'bb', environment: 'sandbox');

  setUp(() async {
    service = await WakeServiceStub.start();
    client = WakeClient();
    addTearDown(() async {
      client.close();
      await service.close();
    });
  });

  test('a registration keeps the secret and sends only the tokens', () async {
    service.statuses.add(201);

    final registration = await client.register(service.uri, tokens);

    expect(registration.handle, 'h');
    expect(registration.secret, 's');
    final (method, path, authorization, body) = service.requests.single;
    expect((method, path, authorization), ('POST', '/v1/devices', null));
    expect(body, {'voip': 'aa', 'apns': 'bb', 'environment': 'sandbox'});
  });

  test('an update the service refuses reports the registration lost', () async {
    service.statuses.addAll([204, 401]);
    final registration =
        WakeRegistration(service: service.uri, handle: 'h', secret: 's');

    expect(await client.update(registration, tokens), isTrue);
    expect(await client.update(registration, tokens), isFalse);
    expect(service.requests.first.$1, 'PUT');
    expect(service.requests.first.$2, '/v1/devices/h');
    expect(service.requests.first.$3, 'Bearer s');
  });

  test(
      'a wake names the call or carries the sealed texts, and an unknown '
      'handle reads as forgotten', () async {
    service.statuses.addAll([202, 202, 404, 429]);
    WakeRequest wake(String? call, {String? preview}) => WakeRequest(
        service: service.uri.toString(),
        handle: 'h',
        chat: 'c',
        callId: call,
        preview: preview);

    expect(await client.wake(wake('call-1')), WakeOutcome.sent);
    expect(await client.wake(wake(null, preview: 'sealed')), WakeOutcome.sent);
    expect(await client.wake(wake(null)), WakeOutcome.forgotten);
    expect(await client.wake(wake(null)), WakeOutcome.refused);
    expect(service.requests.map((request) => request.$4), [
      {'handle': 'h', 'kind': 'call', 'call': 'call-1'},
      {'handle': 'h', 'kind': 'message', 'preview': 'sealed'},
      {'handle': 'h', 'kind': 'message'},
      {'handle': 'h', 'kind': 'message'},
    ]);
  });

  test('a service behind a path prefix keeps it', () async {
    service.statuses.add(202);
    final prefixed = service.uri.replace(path: '/wake');

    await client.wake(WakeRequest(
        service: prefixed.toString(), handle: 'h', chat: 'c', callId: null));

    expect(service.requests.single.$2, '/wake/v1/wake');
  });

  test('an unreachable service is a refusal, not an error', () async {
    final address = service.uri;
    await service.close();

    final outcome = await client.wake(WakeRequest(
        service: address.toString(), handle: 'h', chat: 'c', callId: null));

    expect(outcome, WakeOutcome.refused);
  });
}
