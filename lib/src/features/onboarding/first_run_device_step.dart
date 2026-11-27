import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/shared/inline_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/device_link/device_link_provider.dart';
import 'package:mosh/src/features/device_link/device_link_state.dart';
import 'package:mosh/src/features/device_link/devices_settings_section.dart';

import 'first_run_profile.dart';
import 'first_run_provider.dart';

class FirstRunDeviceStep extends ConsumerStatefulWidget {
  const FirstRunDeviceStep({super.key});
  @override
  ConsumerState<FirstRunDeviceStep> createState() => _FirstRunDeviceStepState();
}

class _FirstRunDeviceStepState extends ConsumerState<FirstRunDeviceStep> {
  String? _error;
  String? _notice;

  Future<void> _continue() async {
    if (ref.read(deviceLinkProvider).value?.busy ?? true) return;
    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      final outcome =
          await ref.read(deviceLinkProvider.notifier).continueSetup(() async {
        if (!mounted) return;
        await ref
            .read(firstRunProfileProvider.notifier)
            .goTo(SetupStep.network);
      });
      if (mounted && outcome == DeviceLinkExit.linkApproved) {
        setState(() => _notice =
            AppLocalizations.of(context)!.firstRunLinkAlreadyApproved);
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = AppLocalizations.of(context)!.firstRunDeviceError);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final device = ref.watch(deviceLinkProvider);
    final link = device.value;
    final pending = link?.pending ?? false;
    final connected = link?.connected ?? false;
    final locked =
        link == null || link.busy || link.delivering || link.readError != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // The card that connects this device to an existing profile is open
      // from the start; going on without it is the button under it.
      if (device.isLoading)
        const Center(child: CircularProgressIndicator())
      else
        const DevicesSettingsSection(joiningOnly: true),
      const SizedBox(height: MoshSpace.s5),
      // One primary button moves on. While a link waits for its answer the
      // way on is to give it up, which is the quiet button.
      if (pending && !connected)
        OutlinedButton(
            onPressed: locked ? null : _continue,
            child: Text(l.firstRunCancelLink))
      else
        FilledButton(
            onPressed: locked ? null : _continue,
            child:
                Text(connected ? l.firstRunContinue : l.firstRunFirstDevice)),
      const SizedBox(height: MoshSpace.s5),
      Center(
        child: TextButton(
            onPressed: locked || pending ? null : () => _back(),
            child: Text(l.firstRunBack)),
      ),
      if (_error != null) InlineError(message: _error),
      if (_notice != null) Semantics(liveRegion: true, child: Text(_notice!)),
    ]);
  }

  Future<void> _back() async {
    if (ref.read(deviceLinkProvider).value?.busy ?? true) return;
    try {
      await ref.read(deviceLinkProvider.notifier).backSetup(() async {
        if (!mounted) return;
        await ref.read(firstRunProfileProvider.notifier).goTo(SetupStep.name);
      });
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = AppLocalizations.of(context)!.firstRunSaveError);
      }
    }
  }
}
