import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/attachment_launcher.dart';
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

/// Writes the log for sharing and answers its path; `null` while empty.
final fieldLogExportProvider = Provider<Future<String?> Function()>((ref) {
  final bridge = ref.watch(bridgeFacadeProvider);
  return () async => (await exportFieldLog(bridge, Directory.systemTemp))?.path;
});

/// Sends an exported log file on; [origin] anchors an iPad's popover.
typedef FieldLogSend = Future<void> Function(String path, Rect? origin);

/// The system share sheet. Linux has none for files (share_plus), so there
/// the log opens in the text editor instead.
final fieldLogSendProvider = Provider<FieldLogSend>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    final launcher = ref.watch(attachmentLauncherProvider);
    return (path, _) => launcher.open(path);
  }
  return (path, origin) => SharePlus.instance.share(ShareParams(
        files: [XFile(path, mimeType: 'text/plain')],
        sharePositionOrigin: origin,
      ));
});

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

  /// One export at a time: two would rewrite the same file under each other.
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final problem = _problem;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          icon: const Icon(MoshIcons.share),
          label: Text(l.fieldLogShare),
          onPressed: _sharing ? null : () => _share(context, l),
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
    setState(() {
      _problem = null;
      _sharing = true;
    });
    String? problem;
    try {
      final export = await ref.read(fieldLogExportProvider)();
      if (export == null) {
        problem = l.fieldLogEmpty;
      } else {
        await ref.read(fieldLogSendProvider)(export, origin);
      }
    } catch (error) {
      debugPrint('mosh: field log not shared: $error');
      problem = l.fieldLogFailed;
    }
    if (mounted) {
      setState(() {
        _problem = problem;
        _sharing = false;
      });
    }
  }
}
