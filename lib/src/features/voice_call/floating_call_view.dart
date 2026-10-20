import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'call_video_renderer.dart';
import 'call_video_stage.dart';
import 'call_view_state.dart';

class FloatingCallView extends StatelessWidget {
  const FloatingCallView(
      {super.key,
      required this.call,
      required this.images,
      required this.onRestore,
      required this.onEnd});
  final CallViewState call;
  final ValueListenable<CallVideoImages> images;
  final VoidCallback? onRestore;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Expanded(
            child: Semantics(
                label: l.callFloatingVideo,
                child: InkWell(
                    onTap: onRestore,
                    child: CallVideoStage(
                        images: images,
                        peer: call.peer,
                        remoteCamera: call.media?.remoteCamera == true,
                        alwaysVisible: true,
                        inset: false)))),
        Row(children: [
          IconButton(
              tooltip: l.callShowWindow,
              onPressed: onRestore,
              icon: const Icon(Icons.open_in_full, size: 20)),
          Expanded(
              child: Text(call.peer,
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
          IconButton(
              tooltip: l.callActiveHangUp,
              onPressed: onEnd,
              color: MoshColors.danger,
              icon: const Icon(Icons.call_end, size: 20)),
        ]),
      ]),
    );
  }
}
