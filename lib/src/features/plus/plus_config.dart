/// The issuer pin is build configuration, never learned from an HTTP response.
class PlusConfig {
  const PlusConfig(
      {required this.issuerKey, this.serverUrl = '', this.mainnet = false});
  final String issuerKey;
  final String serverUrl;
  final bool mainnet;
  bool get enabled => issuerKey.isNotEmpty;
  bool get canPurchase => enabled && serverUrl.isNotEmpty;

  Uri get server {
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
