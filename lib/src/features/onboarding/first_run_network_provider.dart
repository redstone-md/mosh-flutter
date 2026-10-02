import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/rust/network_inventory.dart';
import 'package:mosh/src/state/gateway_provider.dart';

class SetupNetwork {
  const SetupNetwork(
      {required this.interfaces,
      required this.savedAdapter,
      required this.liveAdapter,
      required this.vpnDetected});
  final List<NetworkInterfaceInfo> interfaces;
  final String? savedAdapter;
  final String? liveAdapter;
  final bool vpnDetected;
}

final setupNetworkProvider =
    FutureProvider.autoDispose<SetupNetwork>((ref) async {
  final bridge = ref.watch(bridgeFacadeProvider);
  final (interfaces, consent, binding, detection) = await (
    bridge.listInterfaces(),
    bridge.getVpnBypassConsent(),
    bridge.getBindInterface(),
    bridge.detectVpn(),
  ).wait;
  return SetupNetwork(
      interfaces: interfaces,
      savedAdapter: consent?.interface_,
      liveAdapter: binding,
      vpnDetected: detection.vpnOwnsDefaultRoute);
});
