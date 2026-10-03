import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/features/device_link/device_link_provider.dart';
import 'package:mosh/src/features/device_link/device_link_state.dart';

import 'scriptable_device_link.dart';

/// Real notifier, explicit refresh and scripted native commands.
class DeviceLinkHarness {
  DeviceLinkHarness({ScriptableDeviceLink? commands})
      : commands = commands ?? ScriptableDeviceLink() {
    container = ProviderContainer(retry: (_, __) => null, overrides: [
      deviceLinkCommandsProvider.overrideWithValue(this.commands),
      deviceLinkPollIntervalProvider.overrideWithValue(null),
    ]);
    container.listen(deviceLinkProvider, (_, __) {});
  }

  final ScriptableDeviceLink commands;
  late final ProviderContainer container;
  DeviceLinkController get controller =>
      container.read(deviceLinkProvider.notifier);
  DeviceLinkState get state => container.read(deviceLinkProvider).requireValue;
  Future<DeviceLinkState> get ready =>
      container.read(deviceLinkProvider.future);

  void replaceCommands(ScriptableDeviceLink replacement) {
    container.updateOverrides([
      deviceLinkCommandsProvider.overrideWithValue(replacement),
      deviceLinkPollIntervalProvider.overrideWithValue(null),
    ]);
  }

  void dispose() => container.dispose();
}
