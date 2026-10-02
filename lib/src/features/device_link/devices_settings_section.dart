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
import 'device_list.dart';
import 'device_qr_scanner.dart';
import 'device_revocation_dialog.dart';
import 'qr_image.dart';

class DevicesSettingsSection extends ConsumerStatefulWidget {
  const DevicesSettingsSection({super.key});

  @override
  ConsumerState<DevicesSettingsSection> createState() =>
      _DevicesSettingsSectionState();
}

class _DevicesSettingsSectionState
    extends ConsumerState<DevicesSettingsSection> {
  bool _busy = false;
  bool _joining = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        setState(() => _error = error is FormatException
            ? l.deviceLinkInvalidQr
            : deviceLinkError(l, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join(String uri) async {
    if (!mounted) return;
    await ref
        .read(deviceLinkProvider.notifier)
        .joinLink(uri.trim(), _deviceName());
    if (mounted) setState(() => _joining = false);
  }

  Future<void> _importImage() async {
    final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp']);
    if (file == null) return;
    if (file.size > 10 * 1024 * 1024) {
      throw const FormatException('Invalid QR image');
    }
    await _join(await decodeDeviceQr(await file.readAsBytes()));
  }

  Future<void> _scan() async {
    final uri = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const DeviceQrScanner()));
    if (uri != null) await _join(uri);
  }

  Future<void> _cancel() async {
    await ref.read(deviceLinkProvider.notifier).cancel();
    if (mounted) setState(() => _joining = false);
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
          data: (snapshot) => _body(l, snapshot),
        );
  }

  Widget _body(AppLocalizations l, DeviceLinkSnapshot s) {
    final idle = s.phase == DeviceLinkPhase.idle ||
        s.phase == DeviceLinkPhase.failed ||
        s.phase == DeviceLinkPhase.linked;
    final role = _joining ? DeviceLinkRole.joining : s.role;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LinkedDeviceList(
          snapshot: s,
          onRemove: idle && !_busy && !s.revoked ? _removeDevice : null),
      const SizedBox(height: 24),
      if (s.phase == DeviceLinkPhase.linked) ...[
        Text(l.deviceLinkSuccess),
        const SizedBox(height: 16),
      ],
      if (_error != null || s.error != null) ...[
        Semantics(
          liveRegion: true,
          child: Text(_error ?? deviceLinkErrorKind(l, s.error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        const SizedBox(height: 12),
      ],
      if (role == null || idle && !_joining)
        _start(s)
      else
        _flow(s, idle, role),
      if (_busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
      ],
    ]);
  }

  Widget _start(DeviceLinkSnapshot s) => DeviceLinkStartActions(
        canJoin: s.canJoin,
        revoked: s.revoked,
        onAuthorize: _busy
            ? null
            : () => _run(ref.read(deviceLinkProvider.notifier).beginLink),
        onJoin: _busy
            ? null
            : () => setState(() {
                  _joining = true;
                  _error = null;
                }),
      );

  Widget _flow(DeviceLinkSnapshot s, bool idle, DeviceLinkRole role) =>
      DeviceLinkFlow(
        snapshot: s,
        role: role,
        busy: _busy,
        onApprove: (code) =>
            _run(() => ref.read(deviceLinkProvider.notifier).approve(code)),
        onCancel: () => _run(_cancel),
        importForm: idle
            ? DeviceLinkImportForm(
                busy: _busy,
                onSubmit: (uri) => _run(() => _join(uri)),
                onImage: () => _run(_importImage),
                onScan: Platform.isAndroid ? () => _run(_scan) : null,
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
