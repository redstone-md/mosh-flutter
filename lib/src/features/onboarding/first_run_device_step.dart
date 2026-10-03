import 'package:flutter/material.dart';
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
  bool _connecting = false;
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
      if (link == null ||
          _connecting ||
          pending ||
          connected ||
          link.readError != null) ...[
        if (device.isLoading)
          const Center(child: CircularProgressIndicator())
        else
          DevicesSettingsSection(
              joiningOnly: true,
              onCancelled: () => setState(() => _connecting = false)),
        const SizedBox(height: 20),
      ] else ...[
        OutlinedButton.icon(
            onPressed: locked ? null : () => setState(() => _connecting = true),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(l.firstRunConnectDevice)),
        const SizedBox(height: 12),
      ],
      if (connected)
        FilledButton(
            onPressed: locked ? null : _continue,
            child: Text(l.firstRunContinue))
      else
        OutlinedButton(
            onPressed: locked ? null : _continue,
            child:
                Text(pending ? l.firstRunCancelLink : l.firstRunFirstDevice)),
      const SizedBox(height: 12),
      TextButton(
          onPressed: locked || pending ? null : () => _back(),
          child: Text(l.firstRunBack)),
      if (_error != null)
        Semantics(
            liveRegion: true,
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
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
