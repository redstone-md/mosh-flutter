import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/plus/plus_config.dart';

void main() {
  PlusConfig read(String serverUrl) => PlusConfig.checked(
      issuerKey: 'issuer', serverUrl: serverUrl, network: 'solana-devnet');

  test('a build with an unusable billing server fails where it is read', () {
    for (final url in ['ftp://billing.example', 'https://billing.example/x']) {
      expect(() => read(url), throwsFormatException, reason: url);
    }
  });

  test('a usable billing server or none at all reads', () {
    expect(read('https://billing.example').canPurchase, isTrue);
    expect(read('').canPurchase, isFalse);
  });
}
