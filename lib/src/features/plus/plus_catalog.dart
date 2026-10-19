class PlusCatalog {
  PlusCatalog._(this.network, this.product, this.recipient, this.issuerKeyId,
      this.assets, this.purchasesEnabled, this.supportUrl, this.termsUrl);

  factory PlusCatalog.fromJson(Map<String, dynamic> json, String pin,
      {bool mainnet = false}) {
    final network = mainnet ? 'solana-mainnet' : 'solana-devnet';
    final product = mainnet ? 'mosh-plus-supporter-30d' : 'mosh-plus-30d';
    if (json['network'] != network ||
        json['product'] != product ||
        json['issuer_public_key_b64'] != pin ||
        json['recipient'] is! String ||
        mainnet &&
            (json['version'] != 2 ||
                json['issuer_key_id'] is! String ||
                !RegExp(r'^[a-f0-9]{64}$')
                    .hasMatch(json['issuer_key_id'] as String))) {
      throw const FormatException('Untrusted Mosh+ catalog');
    }
    final assets = mainnet
        ? (json['assets'] as List)
            .map((item) =>
                PlusAsset.fromJson(item as Map<String, dynamic>, mainnet: true))
            .toList()
        : [
            PlusAsset.fromJson({
              'id': 'TEST',
              'mint': json['mint'],
              'decimals': json['token_decimals'],
              'amount_atomic': json['amount_atomic']
            })
          ];
    if (mainnet &&
        (assets.length != 2 || assets.map((a) => a.id).toSet().length != 2)) {
      throw const FormatException('Invalid Mosh+ payment assets');
    }
    return PlusCatalog._(
        network,
        product,
        json['recipient'] as String,
        mainnet ? json['issuer_key_id'] as String : null,
        List.unmodifiable(assets),
        !mainnet || json['purchases_enabled'] == true,
        _publicLink(json['support_url']),
        _publicLink(json['terms_url']));
  }

  final String network;
  final String product;
  final String recipient;
  final String? issuerKeyId;
  final List<PlusAsset> assets;
  final bool purchasesEnabled;
  final Uri? supportUrl;
  final Uri? termsUrl;
  String get mint => assets.first.mint;
  String get amountAtomic => assets.first.amountAtomic;
  String get amount => assets.first.amount;

  void validateOrder(Map<String, dynamic> json) {
    final mainnet = network == 'solana-mainnet';
    final selected =
        assets.where((asset) => !mainnet || asset.id == json['asset']);
    if (json['recipient'] != recipient ||
        json['network'] != network ||
        json['product'] != product ||
        mainnet && json['issuer_key_id'] != issuerKeyId ||
        selected.length != 1 ||
        json['mint'] != selected.single.mint ||
        json['amount_atomic'] != selected.single.amountAtomic ||
        mainnet && json['token_decimals'] != selected.single.decimals) {
      throw const FormatException('Mosh+ quote changed');
    }
  }
}

Uri? _publicLink(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Invalid Mosh+ purchase link');
  }
  final uri = Uri.parse(value);
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw const FormatException('Invalid Mosh+ purchase link');
  }
  return uri;
}

class PlusAsset {
  PlusAsset.fromJson(Map<String, dynamic> json, {bool mainnet = false})
      : id = json['id'] as String,
        mint = json['mint'] as String,
        decimals = json['decimals'] as int,
        amountAtomic = json['amount_atomic'] as String {
    final expected = switch (id) {
      'USDC' => ('EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', 6),
      'CLXAI' => ('ECZV4aRyQKz2zr3ZFB9qeb4EzJbzuMCQZ2gpiBQfoHrK', 9),
      _ => null,
    };
    if (!RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(amountAtomic) ||
        BigInt.parse(amountAtomic) > BigInt.parse('18446744073709551615') ||
        (mainnet
            ? expected == null || expected.$1 != mint || expected.$2 != decimals
            : decimals != 9)) {
      throw const FormatException('Invalid Mosh+ payment asset');
    }
  }

  final String id;
  final String mint;
  final int decimals;
  final String amountAtomic;
  String get amount => formatPlusAmount(amountAtomic, decimals: decimals);
}

String formatPlusAmount(String atomic, {int decimals = 9}) {
  final digits = atomic.padLeft(decimals + 1, '0');
  final fraction = digits
      .substring(digits.length - decimals)
      .replaceFirst(RegExp(r'0+$'), '');
  return digits.substring(0, digits.length - decimals) +
      (fraction.isEmpty ? '' : '.$fraction');
}
