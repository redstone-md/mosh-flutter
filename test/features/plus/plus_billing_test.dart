import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/plus/plus_billing.dart';
import 'package:mosh/src/features/plus/plus_catalog.dart';
import 'package:mosh/src/features/plus/plus_config.dart';
import '../../support/plus/fakes.dart';

void main() {
  test('HTTP order access uses a bearer and never follows a redirect',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = PlusBilling(PlusConfig(
        issuerKey: 'pin', serverUrl: 'http://127.0.0.1:${server.port}'));
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });
    var redirect = false;
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.toString());
      if (request.uri.path.endsWith('/refresh')) {
        expect(request.headers.value('authorization'),
            'Bearer private-order-token');
      }
      if (redirect) {
        request.response.statusCode = 307;
        request.response.headers.set('location', '/stolen');
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(testOrder));
      }
      await request.response.close();
    });
    final native = MemoryPlusCommands();
    final saved = await native.saveOrder(await client.create());
    expect((await client.refresh(saved.order!))['id'], 'test-order');
    redirect = true;
    await expectLater(
        client.refresh(saved.order!), throwsA(isA<HttpException>()));
    expect(paths, [
      '/v1/orders',
      '/v1/orders/test-order/refresh',
      '/v1/orders/test-order/refresh'
    ]);
  });

  test('pilot accepts HTTPS or loopback HTTP and pins catalog metadata', () {
    for (final url in [
      'http://example.com',
      'ftp://localhost',
      'https://a.test/?x=1',
      'https://user@a.test'
    ]) {
      expect(() => PlusConfig(issuerKey: 'pin', serverUrl: url).server,
          throwsFormatException);
    }
    expect(
        const PlusConfig(issuerKey: 'pin', serverUrl: 'https://billing.example')
            .server
            .scheme,
        'https');
    final catalog = {
      ...testOrder,
      'token_decimals': 9,
      'issuer_public_key_b64': 'pin'
    };
    expect(PlusCatalog.fromJson(catalog, 'pin').amount, '1.000000001');
    expect(() => PlusCatalog.fromJson(catalog, 'other-pin'),
        throwsFormatException);
    expect(
        () => PlusCatalog.fromJson(
            {...catalog, 'network': 'solana-mainnet'}, 'pin'),
        throwsFormatException);
    expect(
        () => PlusCatalog.fromJson(catalog, 'pin')
            .validateOrder({...testOrder, 'amount_atomic': '2'}),
        throwsFormatException);
  });
}
