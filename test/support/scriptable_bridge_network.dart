part of 'scriptable_bridge.dart';

mixin _BridgeNetwork on _ScriptableBridgeState {
  @override
  Future<List<NetworkInterfaceInfo>> listInterfaces() =>
      runScripted(BridgeMethod.listInterfaces, const {}, () => _interfaces);

  @override
  Future<VpnDetection> detectVpn() => runScripted(BridgeMethod.detectVpn,
      const {}, () => _vpnDetection ?? cannedVpnDetection());

  @override
  Future<String?> getBindInterface() => runScripted(
      BridgeMethod.getBindInterface, const {}, () => _bindInterface);

  @override
  Future<VpnBypassConsent?> getVpnBypassConsent() => runScripted(
      BridgeMethod.getVpnBypassConsent, const {}, () => _vpnConsent);

  @override
  Future<void> setVpnBypassConsent({String? interfaceName}) => runScripted(
          BridgeMethod.setVpnBypassConsent, {'interfaceName': interfaceName},
          () {
        final name = interfaceName;
        _vpnConsent = (name == null || name.isEmpty)
            ? null
            : VpnBypassConsent(interface_: name, index: 0);
      });
}
