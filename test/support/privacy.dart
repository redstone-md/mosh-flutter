import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mosh/src/features/crash_reporting/crash_reporting.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import 'scriptable_bridge.dart';

/// Real consent/controller behavior with scripted storage and a local SDK.
class PrivacyFixture {
  PrivacyFixture({this.available = true});

  final bool available;
  final bridge = ScriptableBridge();
  final sdkEvents = <String>[];
  bool failStart = false;

  late final reporting = CrashReporting(
    bridge: bridge,
    dsn: available ? 'test-dsn' : '',
    start: (dsn, salt) async {
      sdkEvents.add('start');
      if (failStart) throw StateError('SDK unavailable');
    },
    stop: () async => sdkEvents.add('stop'),
    capture: (_) {},
  );

  List<Override> get overrides => [
        bridgeFacadeProvider.overrideWithValue(bridge),
        crashReportingProvider.overrideWithValue(reporting),
      ];

  Future<void> dispose() async => await bridge.rustPanics.close();
}
