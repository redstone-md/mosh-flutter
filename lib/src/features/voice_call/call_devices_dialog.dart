import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
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
      availableWhileLocked: true,
      builder: (context) => MoshDialog(
          title: l.callDevices,
          closeLabel: l.dialogClose,
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: MoshSpace.s4,
              children: [
                _select(
                    context,
                    call,
                    l.callMicrophone,
                    media.input,
                    media.inputs,
                    CallViewAction.selectInput,
                    l.callDefaultDevice),
                _select(
                    context,
                    call,
                    l.callSpeaker,
                    media.output,
                    media.outputs,
                    CallViewAction.selectOutput,
                    l.callDefaultDevice),
                _select(
                    context,
                    call,
                    l.callCamera,
                    media.cameraId,
                    media.cameras,
                    CallViewAction.selectCamera,
                    l.callDefaultDevice),
                if (media.diagnostics != null)
                  Text(media.diagnostics!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: MoshColors.of(context).onSurfaceMuted)),
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
    Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MoshSpace.s2,
        children: [
          // The select names itself to a screen reader.
          ExcludeSemantics(
              child: Text(label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: MoshColors.of(context).onSurfaceVariant))),
          MoshSelect<String?>(
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
                      .pop(call.command(action, deviceId: id))),
        ]);
