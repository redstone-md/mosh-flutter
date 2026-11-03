import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/lock/mosh_lock_screen.dart';
import '../../support/pump.dart';

void main() {
  final cases = <String, String>{
    'DEK_STORAGE_UNAVAILABLE': 'Authentication failed repeatedly.',
    'DEK_ENVELOPE_INVALID': 'Authentication failed repeatedly.',
    'UNKNOWN_FAILURE': 'Authentication failed repeatedly.',
    'AUTHENTICATION_CANCELED': 'Biometric authentication was canceled.',
    'cancel': 'Biometric authentication was canceled.',
    'canceled': 'Biometric authentication was canceled.',
    'cancelled': 'Biometric authentication was canceled.',
    'AUTHENTICATION_CANCELLED': 'Biometric authentication was canceled.',
    'BIOMETRIC_UNAVAILABLE': 'Device not secured',
  };
  for (final entry in cases.entries) {
    testWidgets('retry classifies ${entry.key} without exposing chats',
        (tester) async {
      var swaps = 0;
      await pumpScreen(
          tester,
          MoshLockScreen(
              retry: () async => throw PlatformException(code: entry.key),
              swapTo: (_) => swaps++,
              nextApp: const SizedBox()));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining(entry.value), findsOneWidget);
      expect(swaps, 0);
      if (entry.key == 'BIOMETRIC_UNAVAILABLE') {
        expect(find.text('Retry'), findsNothing);
      }
    });
  }
}
