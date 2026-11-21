// Figma capture for the account area: Devices, Mosh+ and the VPN consent.
import 'account_devices.dart';
import 'account_plus.dart';
import 'account_vpn.dart';
import 'harness.dart';

void main() {
  figmaScenes('account', [...deviceScenes, ...plusScenes, ...vpnScenes]);
}
