import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/state/gateway_provider.dart';

/// The one file the log is shared as; rewritten on every share.
const String _exportName = 'mosh-log.txt';

/// Joins the field log's files, oldest first, into one text file in
/// [directory]. `null` while nothing has been logged.
Future<File?> exportFieldLog(BridgeFacade bridge, Directory directory) async {
  final files = await bridge.logFiles();
  if (files.isEmpty) return null;
  final export = File('${directory.path}/$_exportName');
  final sink = export.openWrite();
  try {
    for (final path in files.reversed) {
      await sink.addStream(File(path).openRead());
    }
  } finally {
    await sink.close();
  }
  return export;
}

/// Hands the field log to the system share sheet, so the user decides where
/// it goes. Works without a running runtime, so the failed-launch screen
/// offers it too.
class FieldLogButton extends ConsumerStatefulWidget {
  const FieldLogButton({super.key});

  @override
  ConsumerState<FieldLogButton> createState() => _FieldLogButtonState();
}

class _FieldLogButtonState extends ConsumerState<FieldLogButton> {
  String? _problem;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final problem = _problem;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          icon: const Icon(Icons.share_outlined),
          label: Text(l.fieldLogShare),
          onPressed: () => _share(context, l),
        ),
        if (problem != null)
          Text(problem, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Future<void> _share(BuildContext context, AppLocalizations l) async {
    // An iPad anchors the share popover to the button.
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _problem = null);
    String? problem;
    try {
      final export = await exportFieldLog(
          ref.read(bridgeFacadeProvider), Directory.systemTemp);
      if (export == null) {
        problem = l.fieldLogEmpty;
      } else {
        await SharePlus.instance.share(ShareParams(
          files: [XFile(export.path, mimeType: 'text/plain')],
          sharePositionOrigin: origin,
        ));
      }
    } catch (error) {
      debugPrint('mosh: field log not shared: $error');
      problem = l.fieldLogFailed;
    }
    if (mounted) setState(() => _problem = problem);
  }
}
