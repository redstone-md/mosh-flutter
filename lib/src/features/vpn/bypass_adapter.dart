// bypass_adapter: pure helpers that pick which physical adapter the Moss
// node should bind to when the user has not chosen one, so traffic leaves
// the VPN tunnel. Used by `VpnConsentModal` (the default-adapter
// suggestion) and `BindInterfaceField` (advanced settings). Pure + free of
// any I/O so the policy is unit-testable without the network inventory.

library;

import 'package:mosh/src/rust/network_inventory.dart' show NetworkInterfaceInfo;

/// Link-local IPv4 prefix (169.254.x.x). Windows hands these out when
/// DHCP never answered, so the NIC is "up" and has an address while being
/// connected to nothing -- exactly the adapter that must not win the
/// bypass.
const String apipaPrefix = '169.254.';

/// Adapters that can carry Moss around a tunnel: up + non-loopback +
/// non-virtual + has an IPv4 + IPv4 not in the APIPA range.
List<NetworkInterfaceInfo> bypassCandidates(
  List<NetworkInterfaceInfo> list,
) =>
    list
        .where(
          (iface) =>
              iface.isUp &&
              !iface.isLoopback &&
              !iface.isVirtual &&
              iface.ipv4 != null &&
              iface.ipv4!.isNotEmpty &&
              !iface.ipv4!.startsWith(apipaPrefix),
        )
        .toList(growable: false);

/// The adapter to bind to when nobody has chosen one: any candidate
/// leaves the tunnel, so the first is as good as the last -- there is
/// nothing here for the user to get right, which is the point. Returns an
/// empty string when no candidate exists.
String defaultBypassAdapter(List<NetworkInterfaceInfo> list) {
  final candidates = bypassCandidates(list);
  return candidates.isEmpty ? '' : candidates.first.name;
}

/// Human label for an interface in pickers/the modal: `name - ipv4` when
/// an IPv4 is set, else just `name`.
String adapterLabel(NetworkInterfaceInfo iface) {
  final ip = iface.ipv4;
  return (ip != null && ip.isNotEmpty) ? '${iface.name} - $ip' : iface.name;
}
