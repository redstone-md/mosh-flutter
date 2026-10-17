class PlusCatalog {
  PlusCatalog.fromJson(Map<String, dynamic> json, String pin)
      : mint = json['mint'] as String,
        recipient = json['recipient'] as String,
        amountAtomic = json['amount_atomic'] as String {
    if (json['network'] != 'solana-devnet' ||
        json['product'] != 'mosh-plus-30d' ||
        json['token_decimals'] != 9 ||
        json['issuer_public_key_b64'] != pin ||
        !RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(amountAtomic) ||
        BigInt.parse(amountAtomic) > BigInt.parse('18446744073709551615')) {
      throw const FormatException('Untrusted Mosh+ catalog');
    }
  }
  final String mint;
  final String recipient;
  final String amountAtomic;

  String get amount => formatPlusAmount(amountAtomic);

  void validateOrder(Map<String, dynamic> json) {
    if (json['mint'] != mint ||
        json['recipient'] != recipient ||
        json['amount_atomic'] != amountAtomic ||
        json['network'] != 'solana-devnet' ||
        json['product'] != 'mosh-plus-30d') {
      throw const FormatException('Mosh+ quote changed');
    }
  }
}

String formatPlusAmount(String atomic) {
  final digits = atomic.padLeft(10, '0');
  final fraction =
      digits.substring(digits.length - 9).replaceFirst(RegExp(r'0+$'), '');
  return digits.substring(0, digits.length - 9) +
      (fraction.isEmpty ? '' : '.$fraction');
}
