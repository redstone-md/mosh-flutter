import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/features/voice_call/system_call_binding.dart';
import 'package:mosh/src/features/wake/wake_sender.dart';
import 'package:mosh/src/features/wake/wake_services.dart';
import 'package:mosh/src/platform/ios_system_calls.dart';
import 'package:mosh/src/state/auto_poll_provider.dart';

/// What runs for the life of the process whether or not a window shows. A
/// push starts the iPhone app with no window and no frames, so the call it
/// rings must not depend on a widget being built.
final processServicesProvider = Provider<void>((ref) {
  ref.watch(wakeSenderProvider);
  ref.watch(wakeRegistrationProvider);
  if (ref.watch(iosSystemCallsProvider) != null) {
    ref.watch(autoPollProvider);
    ref.watch(systemCallMirrorProvider);
  }
});
