import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/plus/plus_catalog.dart';

void main() {
  test(
      'production checkout keeps each mint, decimals and fixed atomic quote together',
      () {
    final json = <String, dynamic>{
      'version': 2,
      'network': 'solana-mainnet',
      'product': 'mosh-plus-supporter-30d',
      'recipient': 'treasury',
      'issuer_key_id': 'a' * 64,
      'issuer_public_key_b64': 'pin',
      'assets': [
        {
          'id': 'USDC',
          'mint': 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
          'decimals': 6,
          'amount_atomic': '5000000'
        },
        {
          'id': 'CLXAI',
          'mint': 'ECZV4aRyQKz2zr3ZFB9qeb4EzJbzuMCQZ2gpiBQfoHrK',
          'decimals': 9,
          'amount_atomic': '2575000000000'
        },
      ],
    };
    final catalog = PlusCatalog.fromJson(json, 'pin', mainnet: true);
    expect(catalog.assets.map((asset) => asset.amount), ['5', '2575']);
    final usdc = catalog.assets.first;
    final quote = <String, dynamic>{
      'network': 'solana-mainnet',
      'product': 'mosh-plus-supporter-30d',
      'issuer_key_id': 'a' * 64,
      'recipient': 'treasury',
      'asset': 'USDC',
      'mint': usdc.mint,
      'token_decimals': 6,
      'amount_atomic': '5000000'
    };
    catalog.validateOrder(quote);
    expect(() => catalog.validateOrder({...quote, 'token_decimals': 9}),
        throwsFormatException);
    expect(
        () =>
            catalog.validateOrder({...quote, 'mint': catalog.assets.last.mint}),
        throwsFormatException);
    expect(() => PlusCatalog.fromJson(json, 'other-pin', mainnet: true),
        throwsFormatException);
    expect(
        () => PlusCatalog.fromJson({...json, 'network': 'solana-devnet'}, 'pin',
            mainnet: true),
        throwsFormatException);
  });
}
