import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/features/shared/mosh_dialog.dart';
import 'package:mosh/src/features/shared/mosh_dialog_route.dart';
import 'call_media_view.dart';
import 'call_view_state.dart';

Future<CallViewCommand?> showCallDevices(
    BuildContext context, CallViewState call) {
  final l = AppLocalizations.of(context)!;
  final media = call.media!;
  return showMoshDialog<CallViewCommand>(
      context: context,
      builder: (context) => MoshDialog(
          title: l.callDevices,
          closeLabel: l.dialogClose,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _select(context, call, l.callMicrophone, media.input, media.inputs,
                CallViewAction.selectInput, l.callDefaultDevice),
            const SizedBox(height: 12),
            _select(context, call, l.callSpeaker, media.output, media.outputs,
                CallViewAction.selectOutput, l.callDefaultDevice),
            const SizedBox(height: 12),
            _select(context, call, l.callCamera, media.cameraId, media.cameras,
                CallViewAction.selectCamera, l.callDefaultDevice),
            if (media.diagnostics != null)
              Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(media.diagnostics!,
                      style: Theme.of(context).textTheme.bodySmall)),
          ])));
}

Widget _select(
        BuildContext context,
        CallViewState call,
        String label,
        String? selected,
        List<CallDeviceView> devices,
        CallViewAction action,
        String defaultLabel) =>
    SizedBox(
        width: 320,
        height: 44,
        child: MoshSelect<String?>(
            label: label,
            value: selected,
            options: [
              MoshSelectOption(null, defaultLabel),
              for (final device in devices)
                MoshSelectOption(device.id, device.name)
            ],
            onChanged: call.busy
                ? null
                : (id) => Navigator.of(context)
                    .pop(call.command(action, deviceId: id))));
