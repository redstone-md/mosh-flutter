import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/device_link/device_link_provider.dart';
import 'package:mosh/src/features/device_link/devices_settings_section.dart';
import 'package:mosh/src/rust/device_link/types.dart';

import 'first_run_profile.dart';
import 'first_run_provider.dart';

class FirstRunDeviceStep extends ConsumerStatefulWidget {
  const FirstRunDeviceStep({super.key});
  @override
  ConsumerState<FirstRunDeviceStep> createState() => _FirstRunDeviceStepState();
}

class _FirstRunDeviceStepState extends ConsumerState<FirstRunDeviceStep> {
  bool _connecting = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (!await _settleLink()) return;
      if (!mounted) return;
      await ref.read(firstRunProfileProvider.notifier).goTo(SetupStep.network);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = AppLocalizations.of(context)!.firstRunDeviceError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _settleLink() async {
    final before = await ref.read(deviceLinkProvider.future);
    if (before.phase == DeviceLinkPhase.delivering) return false;
    if (before.role == null || before.phase == DeviceLinkPhase.linked) {
      return true;
    }
    await ref.read(deviceLinkProvider.notifier).cancel();
    if (!mounted) return false;
    final after = await ref.read(deviceLinkProvider.future);
    if (after.phase == DeviceLinkPhase.delivering ||
        after.role != null && after.phase != DeviceLinkPhase.linked) {
      return false;
    }
    if (after.devices.length > before.devices.length ||
        before.canJoin && !after.canJoin) {
      setState(() =>
          _notice = AppLocalizations.of(context)!.firstRunLinkAlreadyApproved);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final snapshot = ref.watch(deviceLinkProvider).value;
    final pending = snapshot?.role != null &&
        snapshot?.phase != DeviceLinkPhase.linked &&
        snapshot?.phase != DeviceLinkPhase.failed;
    final connected = snapshot?.phase == DeviceLinkPhase.linked ||
        (snapshot?.devices.length ?? 0) > 1;
    final locked = _busy ||
        snapshot == null ||
        snapshot.phase == DeviceLinkPhase.delivering;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (snapshot == null || _connecting || pending || connected) ...[
        const DevicesSettingsSection(joiningOnly: true),
        const SizedBox(height: 20),
      ] else ...[
        FilledButton.icon(
            onPressed: locked ? null : () => setState(() => _connecting = true),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(l.firstRunConnectDevice)),
        const SizedBox(height: 12),
      ],
      OutlinedButton(
          onPressed: locked ? null : _continue,
          child: Text(connected
              ? l.firstRunContinue
              : pending
                  ? l.firstRunCancelLink
                  : l.firstRunFirstDevice)),
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
      if (_busy) const LinearProgressIndicator(),
    ]);
  }

  Future<void> _back() async {
    try {
      await ref.read(firstRunProfileProvider.notifier).goTo(SetupStep.name);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = AppLocalizations.of(context)!.firstRunSaveError);
      }
    }
  }
}
