import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/settings/settings_card.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';
import 'package:mosh/src/features/shared/mosh_dialog_route.dart';
import 'package:mosh/src/state/notifications_provider.dart';
import 'package:mosh/src/rust/api/background/types.dart';
import 'android_waiting_owner.dart';

class AndroidWaitingSettings extends ConsumerStatefulWidget {
  const AndroidWaitingSettings({super.key});
  @override
  ConsumerState<AndroidWaitingSettings> createState() =>
      _WaitingSettingsState();
}

class _WaitingSettingsState extends ConsumerState<AndroidWaitingSettings> {
  bool _busy = false, _failed = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(androidWaitingOwnerProvider);
    if (owner == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ListenableBuilder(
        listenable: owner,
        builder: (context, _) => SettingsCard(
          icon: Icons.notifications_active_outlined,
          title: l.settingsBackgroundTitle,
          hint: _availability(owner, l),
          child: _controls(owner, l),
        ),
      ),
    );
  }

  Widget _controls(AndroidWaitingOwner owner, AppLocalizations l) {
    final platform = owner.platform;
    final state = platform.state;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l.settingsBackgroundEnabled),
        value: state?.waitingEnabled ?? false,
        onChanged: _busy || state == null
            ? null
            : (enabled) => _run(() async {
                  await (enabled ? platform.enable() : platform.stop());
                  await owner.refresh();
                }),
      ),
      ..._permissionActions(owner, l),
      const Divider(),
      _previews(owner, l),
      if (owner.failure != null)
        TextButton(
            onPressed: _busy ? null : () => _run(owner.attach),
            child: Text(l.deviceLinkRetry)),
      if (_failed)
        Text(l.settingsBackgroundActionError,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ]);
  }

  List<Widget> _permissionActions(
      AndroidWaitingOwner owner, AppLocalizations l) {
    final platform = owner.platform;
    final state = platform.state;
    return [
      if (state?.waitingEnabled == true && state?.notificationsAllowed != true)
        TextButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      ref.invalidate(notificationsReadyProvider);
                      await ref.read(notificationsReadyProvider.future);
                      await platform.refresh();
                    }),
            child: Text(l.settingsBackgroundNotifications)),
      if (state?.waitingEnabled == true && state?.batteryExempt != true)
        TextButton(
            onPressed: _busy ? null : () => _run(() => _battery(owner, l)),
            child: Text(l.settingsBackgroundBattery)),
    ];
  }

  Widget _previews(AndroidWaitingOwner owner, AppLocalizations l) {
    final platform = owner.platform;
    final state = platform.state;
    return Column(children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l.settingsLockedNotificationNames),
        value: state?.showNamesWhenLocked ?? false,
        onChanged: _busy || state == null
            ? null
            : (enabled) => _run(() => platform.setNotificationPolicy(
                showNamesWhenLocked: enabled,
                showTextWhenLocked: state.showTextWhenLocked)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l.settingsLockedNotificationText),
        value: state?.showTextWhenLocked ?? false,
        onChanged: _busy || state == null
            ? null
            : (enabled) => _run(() => platform.setNotificationPolicy(
                showNamesWhenLocked: state.showNamesWhenLocked,
                showTextWhenLocked: enabled)),
      ),
    ]);
  }

  Future<void> _battery(AndroidWaitingOwner owner, AppLocalizations l) async {
    final agreed = await showMoshDialog<bool>(
        context: context,
        barrierLabel: l.dialogCancel,
        builder: (dialog) => ConfirmDialog(
              title: l.settingsBackgroundBattery,
              body: l.settingsBackgroundBatteryExplanation,
              confirmLabel: l.settingsBackgroundBattery,
              cancelLabel: l.dialogCancel,
              dangerColor: Theme.of(context).colorScheme.primary,
              onCancel: () => Navigator.of(dialog).pop(false),
              onConfirm: () => Navigator.of(dialog).pop(true),
            ));
    if (agreed != true) return;
    await owner.platform.requestBatteryExemption();
  }

  String _availability(AndroidWaitingOwner owner, AppLocalizations l) {
    final state = owner.platform.state;
    final actual = owner.status;
    if (owner.failure != null || state == null || actual?.limitation != null) {
      return l.settingsBackgroundUnavailable;
    }
    if (!state.waitingEnabled) return l.settingsBackgroundOff;
    if (actual?.actualMode == BackgroundMode.unsupported) {
      return l.settingsBackgroundUnsupported;
    }
    if (state.restriction != null ||
        !state.serviceRunning ||
        !state.notificationsAllowed ||
        !state.batteryExempt) {
      return l.settingsBackgroundLimited;
    }
    if (state.interactive) return l.settingsBackgroundForeground;
    return switch (actual?.reachability) {
      BackgroundReachability.ready => l.settingsBackgroundReady,
      BackgroundReachability.attaching => l.settingsBackgroundAttaching,
      _ => l.settingsBackgroundUnavailable,
    };
  }
}
