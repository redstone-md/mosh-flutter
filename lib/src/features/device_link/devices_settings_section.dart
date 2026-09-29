import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/device_link/types.dart';
import 'device_link_copy.dart';
import 'device_link_provider.dart';
import 'device_link_qr.dart';
import 'device_list.dart';
import 'device_revocation_dialog.dart';
import 'qr_image.dart';

const _imageExtensions = ['png', 'jpg', 'jpeg', 'webp'];
const _maxImageBytes = 10 * 1024 * 1024;
const _invalidImage = 'Invalid QR image';

class DevicesSettingsSection extends ConsumerStatefulWidget {
  const DevicesSettingsSection({super.key});

  @override
  ConsumerState<DevicesSettingsSection> createState() =>
      _DevicesSettingsSectionState();
}

class _DevicesSettingsSectionState
    extends ConsumerState<DevicesSettingsSection> {
  final _uri = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _linkOther = false;
  String? _error;

  @override
  void dispose() {
    _uri.dispose();
    _code.dispose();
    super.dispose();
  }

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
        setState(() => _error = error is FormatException
            ? AppLocalizations.of(context)!.deviceLinkInvalidQr
            : deviceLinkError(AppLocalizations.of(context)!, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importImage() async {
    final file = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: _imageExtensions);
    if (file == null) return;
    if (file.size > _maxImageBytes) {
      throw const FormatException(_invalidImage);
    }
    final uri = await decodeDeviceQr(await file.readAsBytes());
    if (mounted) await ref.read(deviceLinkProvider.notifier).importQr(uri);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final snapshot = ref.watch(deviceLinkProvider);
    return snapshot.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(deviceLinkError(l, error)),
        TextButton(
            onPressed: () => ref.invalidate(deviceLinkProvider),
            child: Text(l.deviceLinkRetry)),
      ]),
      data: (s) => _body(l, s),
    );
  }

  Widget _body(AppLocalizations l, DeviceLinkSnapshot s) {
    final controller = ref.read(deviceLinkProvider.notifier);
    final idle = s.phase == DeviceLinkPhase.idle ||
        s.phase == DeviceLinkPhase.failed ||
        s.phase == DeviceLinkPhase.linked;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LinkedDeviceList(
          snapshot: s,
          onRemove: idle && !_busy && !s.revoked ? _removeDevice : null),
      if (s.revoked) ...[
        const SizedBox(height: 8),
        Text(l.deviceLinkRevokedBody),
      ],
      const SizedBox(height: 16),
      Text(_status(l, s), semanticsLabel: _status(l, s)),
      if (s.error != null || _error != null) ...[
        const SizedBox(height: 8),
        Text(_error ?? deviceLinkErrorKind(l, s.error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
      if (idle) ..._startActions(l, s, controller),
      if (s.qrUri != null) ..._qr(l, s.qrUri!),
      if (s.confirmationCode != null) ...[
        const SizedBox(height: 12),
        SelectableText(s.confirmationCode!,
            style: Theme.of(context).textTheme.headlineMedium),
      ],
      if (s.phase == DeviceLinkPhase.awaitingApproval)
        ..._approval(l, s, controller),
      if (!idle && s.phase != DeviceLinkPhase.delivering)
        TextButton(
            onPressed: _busy ? null : () => _run(controller.cancel),
            child: Text(l.deviceLinkDecline)),
      if (_busy) const LinearProgressIndicator(),
    ]);
  }

  Future<void> _removeDevice(DeviceDescriptor device) async {
    if (!await confirmDeviceRemoval(context, device.name) || !mounted) return;
    await _run(
        () => ref.read(deviceLinkProvider.notifier).revoke(device.deviceId));
  }

  List<Widget> _qr(AppLocalizations l, String uri) => [
        const SizedBox(height: 16),
        DeviceLinkQr(uri: uri, label: l.deviceLinkQrLabel),
        TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: uri)),
            icon: const Icon(Icons.copy),
            label: Text(l.deviceLinkCopy)),
        Text(l.deviceLinkExpires),
      ];

  /// A fresh device is the one being linked, so its idle text says how to
  /// show its QR; a device in use says where the QR comes from.
  String _status(AppLocalizations l, DeviceLinkSnapshot s) =>
      s.phase == DeviceLinkPhase.idle && s.canJoin && !s.revoked
          ? l.deviceLinkJoinHelp
          : deviceLinkPhase(l, s.phase);

  /// One primary action per role: a fresh device shows its QR, a device in
  /// use imports one. A fresh device can still link another on request.
  List<Widget> _startActions(AppLocalizations l, DeviceLinkSnapshot s,
          DeviceLinkController controller) =>
      [
        if (s.canJoin) ...[
          const SizedBox(height: 16),
          FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => controller.createQr(_deviceName())),
              child:
                  Text(s.revoked ? l.deviceLinkFreshJoin : l.deviceLinkJoin)),
          if (!s.revoked && !_linkOther)
            TextButton(
                onPressed: () => setState(() => _linkOther = true),
                child: Text(l.deviceLinkLinkOther)),
        ],
        if (!s.revoked && (!s.canJoin || _linkOther)) ..._import(l, controller),
      ];

  List<Widget> _import(AppLocalizations l, DeviceLinkController controller) {
    void submit() => _run(() => controller.importQr(_uri.text));
    return [
      const SizedBox(height: 16),
      FilledButton.icon(
          onPressed: _busy ? null : () => _run(_importImage),
          icon: const Icon(Icons.qr_code),
          label: Text(l.deviceLinkImportImage)),
      const SizedBox(height: 8),
      TextField(
          controller: _uri,
          maxLength: 2048,
          textInputAction: TextInputAction.go,
          onSubmitted: _busy ? null : (_) => submit(),
          decoration: InputDecoration(
              labelText: l.deviceLinkPasteLabel,
              counterText: '',
              suffixIcon: IconButton(
                  tooltip: l.deviceLinkImport,
                  onPressed: _busy ? null : submit,
                  icon: const Icon(Icons.arrow_forward)))),
    ];
  }

  List<Widget> _approval(AppLocalizations l, DeviceLinkSnapshot s,
          DeviceLinkController controller) =>
      [
        const SizedBox(height: 16),
        Text(s.pendingDevice?.name ?? l.deviceLinkDeviceName,
            style: Theme.of(context).textTheme.titleMedium),
        TextField(
            controller: _code,
            maxLength: 12,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: l.deviceLinkCodeLabel)),
        FilledButton(
            onPressed:
                _busy ? null : () => _run(() => controller.approve(_code.text)),
            child: Text(l.deviceLinkApprove)),
      ];
}

/// The name the trusted device sees while approving: this computer's
/// hostname. Android answers "localhost", so it sends none and the device
/// keeps its current name.
String _deviceName() {
  final host = Platform.localHostname;
  if (host == 'localhost') return '';
  return host.length > 64 ? host.substring(0, 64) : host;
}
