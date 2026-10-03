import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/rust/network_inventory.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/features/vpn/network_choice_provider.dart';

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
  final routing =
      await ref.read(networkChoiceProvider(bridge).notifier).readRouting();
  return SetupNetwork(
      interfaces: routing.saved.interfaces,
      savedAdapter: routing.saved.adapter,
      liveAdapter: routing.liveAdapter,
      vpnDetected: routing.vpnDetected);
});
