// Unit tests for `bypass_adapter` (lib/src/features/vpn/
// bypass_adapter.dart).
// Asserts the APIPA exclusion, the up/loopback/virtual filters, the
// first-candidate default, and the adapter-label formatting.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/vpn/bypass_adapter.dart';
import 'package:mosh/src/rust/network_inventory.dart';

NetworkInterfaceInfo _iface({
  required String name,
  String? ipv4,
  bool isUp = true,
  bool isLoopback = false,
  bool isVirtual = false,
}) =>
    NetworkInterfaceInfo(
      name: name,
      description: '',
      index: 0,
      ipv4: ipv4,
      isLoopback: isLoopback,
      isUp: isUp,
      isVirtual: isVirtual,
      isVpn: false,
      isDefaultRoute: false,
    );

void main() {
  group('bypassCandidates', () {
    test('keeps a physical up NIC with a routable IPv4', () {
      final list = [_iface(name: 'eth0', ipv4: '192.168.1.5')];
      expect(bypassCandidates(list).map((i) => i.name), ['eth0']);
    });

    test('drops a down NIC', () {
      final list = [_iface(name: 'eth0', ipv4: '10.0.0.1', isUp: false)];
      expect(bypassCandidates(list), isEmpty);
    });

    test('drops a loopback NIC', () {
      final list = [_iface(name: 'lo', ipv4: '127.0.0.1', isLoopback: true)];
      expect(bypassCandidates(list), isEmpty);
    });

    test('drops a virtual NIC (tunnel / VM host adapter)', () {
      final list = [_iface(name: 'vtun0', ipv4: '10.8.0.1', isVirtual: true)];
      expect(bypassCandidates(list), isEmpty);
    });

    test('drops a NIC with no IPv4', () {
      final list = [_iface(name: 'eth1', ipv4: null)];
      expect(bypassCandidates(list), isEmpty);
    });

    test('drops an APIPA (169.254.x) NIC', () {
      final list = [_iface(name: 'eth2', ipv4: '169.254.1.1')];
      expect(bypassCandidates(list), isEmpty);
    });

    test('keeps candidates in input order', () {
      final list = [
        _iface(name: 'wifi', ipv4: '192.168.0.2'),
        _iface(name: 'eth', ipv4: '192.168.1.3'),
      ];
      expect(bypassCandidates(list).map((i) => i.name), ['wifi', 'eth']);
    });
  });

  group('defaultBypassAdapter', () {
    test('returns the first candidate name', () {
      final list = [
        _iface(name: 'first', ipv4: '10.0.0.1'),
        _iface(name: 'second', ipv4: '10.0.0.2'),
      ];
      expect(defaultBypassAdapter(list), 'first');
    });

    test('returns an empty string when no candidate exists', () {
      final list = [_iface(name: 'tun', ipv4: '10.8.0.1', isVirtual: true)];
      expect(defaultBypassAdapter(list), '');
    });

    test('returns an empty string for an empty list', () {
      expect(defaultBypassAdapter(<NetworkInterfaceInfo>[]), '');
    });
  });

  group('adapterLabel', () {
    test('formats name - ipv4 when an IPv4 is set', () {
      expect(adapterLabel(_iface(name: 'eth0', ipv4: '192.168.1.5')),
          'eth0 - 192.168.1.5');
    });

    test('returns just the name when there is no IPv4', () {
      expect(adapterLabel(_iface(name: 'eth1', ipv4: null)), 'eth1');
    });

    test('returns just the name when the IPv4 is empty', () {
      expect(adapterLabel(_iface(name: 'eth1', ipv4: '')), 'eth1');
    });
  });
}
