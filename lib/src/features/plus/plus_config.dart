/// The issuer pin is build configuration, never learned from an HTTP response.
class PlusConfig {
  const PlusConfig(
      {required this.issuerKey, this.serverUrl = '', this.mainnet = false});

  factory PlusConfig.fromEnvironment() => PlusConfig.checked(
      issuerKey: const String.fromEnvironment('MOSH_PLUS_ISSUER_KEY'),
      serverUrl: const String.fromEnvironment('MOSH_PLUS_SERVER_URL'),
      network: const String.fromEnvironment('MOSH_PLUS_NETWORK',
          defaultValue: 'solana-mainnet'));

  /// Reads build configuration and refuses a value a purchase could not use,
  /// so a misconfigured build fails where its configuration is read, not at
  /// checkout.
  factory PlusConfig.checked(
      {required String issuerKey,
      required String serverUrl,
      required String network}) {
    if (serverUrl.isNotEmpty) _parseServer(serverUrl);
    return PlusConfig(
        issuerKey: issuerKey,
        serverUrl: serverUrl,
        mainnet: switch (network) {
          'solana-mainnet' => true,
          'solana-devnet' => false,
          _ =>
            throw const FormatException('Invalid Mosh+ network configuration'),
        });
  }

  final String issuerKey;
  final String serverUrl;
  final bool mainnet;
  bool get enabled => issuerKey.isNotEmpty;
  bool get canPurchase => enabled && serverUrl.isNotEmpty;

  Uri get server => _parseServer(serverUrl);

  static Uri _parseServer(String serverUrl) {
    final uri = Uri.parse(serverUrl);
    final loopback = ['localhost', '127.0.0.1', '::1'].contains(uri.host);
    if (!(uri.scheme == 'https' || uri.scheme == 'http' && loopback) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != '' && uri.path != '/') {
      throw const FormatException('Invalid Mosh+ server configuration');
    }
    return uri;
  }
}
