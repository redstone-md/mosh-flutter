import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/device_link/types.dart';

import 'device_link_copy.dart';
import 'device_link_flow.dart';
import 'device_link_import_form.dart';
import 'device_link_provider.dart';
import 'device_link_start_actions.dart';
import 'device_link_state.dart';
import 'device_list.dart';
import 'device_qr_scanner.dart';
import 'device_revocation_dialog.dart';
import 'qr_image.dart';

class DevicesSettingsSection extends ConsumerStatefulWidget {
  const DevicesSettingsSection(
      {super.key, this.joiningOnly = false, this.onCancelled});

  /// Setup reuses the importer and protocol UI without authorization actions.
  final bool joiningOnly;

  /// Lets the setup step restore its choices after a successful cancellation.
  final VoidCallback? onCancelled;

  @override
  ConsumerState<DevicesSettingsSection> createState() =>
      _DevicesSettingsSectionState();
}

class _DevicesSettingsSectionState
    extends ConsumerState<DevicesSettingsSection> {
  late bool _joining = widget.joiningOnly;

  /// The workflow exposes failures while retaining the last native proof.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  Future<void> _join(Future<String?> Function() acquire) async {
    final joined = await ref
        .read(deviceLinkProvider.notifier)
        .joinFrom(acquire, _deviceName());
    if (joined && mounted) setState(() => _joining = false);
  }

  Future<String?> _importImage() async {
    final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp']);
    if (file == null) return null;
    if (file.size > 10 * 1024 * 1024) {
      throw const FormatException('Invalid QR image');
    }
    return decodeDeviceQr(await file.readAsBytes());
  }

  Future<String?> _scan() => Navigator.of(context)
      .push<String>(MaterialPageRoute(builder: (_) => const DeviceQrScanner()));

  Future<void> _cancel() async {
    final outcome = await ref.read(deviceLinkProvider.notifier).cancel();
    if (!mounted || outcome != DeviceLinkExit.ready) return;
    setState(() => _joining = false);
    widget.onCancelled?.call();
  }

  Future<void> _removeDevice(DeviceDescriptor device) async {
    if (!await confirmDeviceRemoval(context, device.name) || !mounted) return;
    await _run(
        () => ref.read(deviceLinkProvider.notifier).revoke(device.deviceId));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ref.watch(deviceLinkProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Column(children: [
            Text(deviceLinkError(l, error)),
            TextButton(
                onPressed: () => ref.invalidate(deviceLinkProvider),
                child: Text(l.deviceLinkRetry)),
          ]),
          data: (link) => _body(l, link),
        );
  }

  Widget _body(AppLocalizations l, DeviceLinkState link) {
    final s = link.snapshot;
    final idle = link.idle;
    final role = _joining ? DeviceLinkRole.joining : s.role;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.joiningOnly)
        LinkedDeviceList(
            snapshot: s,
            onRemove: idle && !link.busy && !s.revoked ? _removeDevice : null),
      if (!widget.joiningOnly) const SizedBox(height: 24),
      if (s.phase == DeviceLinkPhase.linked) ...[
        Text(l.deviceLinkSuccess),
        const SizedBox(height: 16),
      ],
      if (link.error != null || s.error != null) ...[
        Semantics(
          liveRegion: true,
          child: Text(
              link.error != null
                  ? deviceLinkError(l, link.error!)
                  : deviceLinkErrorKind(l, s.error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        const SizedBox(height: 12),
      ],
      if (link.readError != null)
        TextButton(
            onPressed: link.busy
                ? null
                : ref.read(deviceLinkProvider.notifier).refresh,
            child: Text(l.deviceLinkRetry)),
      if (widget.joiningOnly && idle && s.canJoin)
        _flow(s, true, DeviceLinkRole.joining, link.busy)
      else if (widget.joiningOnly && idle)
        const SizedBox.shrink()
      else if (role == null || idle && !_joining)
        _start(s, link.busy)
      else
        _flow(s, idle, role, link.busy),
      if (link.busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
      ],
    ]);
  }

  Widget _start(DeviceLinkSnapshot s, bool busy) => DeviceLinkStartActions(
        canJoin: s.canJoin,
        revoked: s.revoked,
        onAuthorize: busy
            ? null
            : () => _run(ref.read(deviceLinkProvider.notifier).beginLink),
        onJoin: busy
            ? null
            : () => setState(() {
                  _joining = true;
                }),
      );

  Widget _flow(
          DeviceLinkSnapshot s, bool idle, DeviceLinkRole role, bool busy) =>
      DeviceLinkFlow(
        snapshot: s,
        role: role,
        busy: busy,
        onApprove: (code) =>
            _run(() => ref.read(deviceLinkProvider.notifier).approve(code)),
        onCancel: () => _run(_cancel),
        importForm: idle
            ? DeviceLinkImportForm(
                busy: busy,
                onSubmit: (uri) => _run(() => _join(() async => uri)),
                onImage: () => _run(() => _join(_importImage)),
                onScan:
                    Platform.isAndroid ? () => _run(() => _join(_scan)) : null,
              )
            : null,
      );
}

/// Android's localhost keeps the existing native name; desktop uses its hostname.
String _deviceName() {
  final host = Platform.localHostname;
  if (host == 'localhost') return '';
  return host.length > 64 ? host.substring(0, 64) : host;
}
