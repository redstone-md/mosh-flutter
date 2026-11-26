import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'call_button.dart';
import 'call_video_stage.dart';
import 'call_video_textures.dart';

/// The Floating call of the Minimized call card: a call with video folds to
/// a tile that shows the picture, can be moved and opens the call when its
/// picture is pressed. MainWindowCallFrame lets the user drag it.
class FloatingCallView extends StatelessWidget {
  const FloatingCallView(
      {super.key,
      required this.peer,
      required this.remoteCamera,
      required this.video,
      required this.onOpen,
      required this.end});

  /// The tile's width where the window has room for the larger one.
  static double width(double room) => room >= 720 ? 320 : 196;

  /// The tile's height at [width]: the 16:9 picture and the foot.
  static double height(BuildContext context, double width) =>
      width * 9 / 16 +
      MoshControl.height(Theme.of(context).platform) +
      MoshSpace.s1 * 2;

  final String peer;
  final bool remoteCamera;
  final ValueListenable<CallVideoPictures> video;
  final VoidCallback? onOpen;
  final CallControl end;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = MoshColors.of(context);
    // Material draws the surface's edge over the picture, which so keeps
    // the tile's whole width.
    return Material(
        color: MoshLevel.popup.fill(colors),
        elevation: MoshLevel.popup.elevation!.dp,
        shape: MoshLevel.popup.shape(colors),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Expanded(
              child: Semantics(
                  label: l.callFloatingVideo,
                  child: InkWell(
                      onTap: onOpen,
                      child: CallVideoStage(
                          video: video,
                          peer: peer,
                          remoteCamera: remoteCamera,
                          alwaysVisible: true)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                MoshSpace.s3, MoshSpace.s1, MoshSpace.s1, MoshSpace.s1),
            child: Row(spacing: MoshSpace.s1, children: [
              Expanded(
                  child: Text(peer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: colors.onSurface))),
              // The phone's tile is too narrow for two buttons: a press on
              // the picture opens the call there.
              if (!MoshControl.touch(theme.platform))
                IconButton(
                    tooltip: l.callExpand,
                    onPressed: onOpen,
                    icon: const Icon(MoshIcons.callExpand)),
              CallMiniButton(control: end),
            ]),
          ),
        ]));
  }
}
