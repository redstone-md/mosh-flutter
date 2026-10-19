import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/plus/plus_billing.dart';
import 'package:mosh/src/features/plus/plus_config.dart';
import 'package:mosh/src/rust/plus/checkout.dart';
import 'package:mosh/src/rust/plus/recovery_types.dart';
import 'package:mosh/src/rust/plus/types.dart';

void main() {
  test(
      'production HTTP keeps series and recovery capabilities out of URLs and retries the native request id',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = 'http://127.0.0.1:${server.port}';
    final client = PlusBilling(
        PlusConfig(issuerKey: 'pin', serverUrl: origin, mainnet: true));
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });
    final requests = <(String, String?, Map<String, dynamic>)>[];
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add((
        request.uri.toString(),
        request.headers.value('authorization'),
        body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>
      ));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'id': 'session',
        'code': 'ABCDEF12',
        'url': '$origin/recover/session',
        'expires_at_ms': 1800057600000,
        'orders': [],
        'next': null
      }));
      await request.response.close();
    });
    const series =
        PlusSeries(id: 'series', accessToken: 'private-series-token');
    const intent =
        PlusCheckoutIntent(requestId: 'durable-request', asset: 'USDC');
    final recovery = PlusRecoverySession(
        id: 'session',
        pollToken: 'private-poll-token',
        publicKeyB64: 'public-key',
        code: 'ABCDEF12',
        expiresAtMs: BigInt.from(1800057600000),
        orders: const [],
        completedOrders: 0);
    await client.registerSeries(series);
    await client.createMainnet(series, intent);
    await client.createMainnet(series, intent);
    await client.startRecovery(series, recovery);
    await client.recoveryStatus(recovery);
    expect(requests[1].$2, 'Bearer private-series-token');
    expect(requests[1].$3['request_id'], 'durable-request');
    expect(requests[2].$3, requests[1].$3);
    expect(requests.last.$2, 'Bearer private-poll-token');
    expect(requests.every((entry) => !entry.$1.contains('private-')), isTrue);
    expect(requests.last.$1, '/v2/recovery/session/status');
    await client.schedule(series);
    await client.recoveryStatus(recovery, after: 'last-order');
    expect(requests.last.$1, '/v2/recovery/session/status?after=last-order');
    await client.recover(
        recovery,
        'owned-order',
        const PlusRecoveryIssuance(
            blindedMessageB64: 'blind',
            destinationSignatureB64: 'destination-proof'));
    expect(requests.last.$1, '/v2/recovery/session/orders/owned-order/issue');
    expect(requests.last.$2, 'Bearer private-poll-token');
    expect(requests.last.$3, {
      'blinded_message_b64': 'blind',
      'destination_signature_b64': 'destination-proof'
    });
  });
}
