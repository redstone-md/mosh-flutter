import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;

import 'call_video_textures.dart';
import 'call_video_surfaces.dart';

/// The Call video stage card: a stage on the lowest tone, as large as what
/// holds it lets it be. It has the shape of the picture that fills it, so a
/// frame from a phone held upright is not shrunk into a wide stage, and is
/// 16:9 until a picture arrives. It shows the other side's video with your own
/// camera in its corner, your camera alone, or who the video is awaited from.
/// Presentation only. Pixel changes never animate; stage presence may fade.
class CallVideoStage extends StatelessWidget {
  const CallVideoStage(
      {super.key,
      required this.video,
      required this.peer,
      this.alwaysVisible = false,
      this.remoteCamera = false});
  final ValueListenable<CallVideoPictures> video;
  final String peer;
  final bool remoteCamera;
  final bool alwaysVisible;

  /// Whether a stage over [pictures] has anything to show.
  static bool shows(CallVideoPictures pictures, {required bool remoteCamera}) =>
      remoteCamera || pictures.remote != null || pictures.local != null;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<CallVideoPictures>(
        valueListenable: video,
        builder: (context, pictures, _) => AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          child: !alwaysVisible && !shows(pictures, remoteCamera: remoteCamera)
              ? const SizedBox.shrink(key: ValueKey(false))
              : _stage(context, pictures),
        ),
      );

  Widget _stage(BuildContext context, CallVideoPictures pictures) {
    final remoteStage = remoteCamera || pictures.remote != null;
    final filling = pictures.remote ?? (remoteStage ? null : pictures.local);
    return AspectRatio(
      key: const ValueKey(true),
      aspectRatio: filling?.aspectRatio ?? 16 / 9,
      child: LayoutBuilder(
          builder: (context, box) => CallVideoSurfaceReport(
              _surfaces(context, box.biggest, remoteStage),
              child: RepaintBoundary(
                  child: ColoredBox(
                      color: MoshColors.of(context).surfaceContainerLowest,
                      child: Stack(
                          fit: StackFit.expand,
                          children: _layers(context, pictures, box.biggest,
                              remoteStage: remoteStage)))))),
    );
  }

  List<Widget> _layers(
      BuildContext context, CallVideoPictures pictures, Size stage,
      {required bool remoteStage}) {
    final remote = pictures.remote;
    final preview = pictures.local;
    final l = AppLocalizations.of(context)!;
    return [
      if (remote != null)
        _picture(remote, l.callRemoteVideo(peer), mirrored: false)
      else if (remoteStage)
        _waiting(context, l.callWaitingForVideo)
      else if (preview != null)
        _picture(preview, l.callLocalPreview, mirrored: true)
      else
        Center(
            child: Semantics(
                label: peer, child: const Icon(MoshIcons.person, size: 32))),
      if (remoteStage && preview != null)
        _preview(context, preview, l.callLocalPreview, stage),
    ];
  }

  /// Who the video is awaited from; a stage too small for it scales it down.
  Widget _waiting(BuildContext context, String status) => Center(
      child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
              padding: const EdgeInsets.all(MoshSpace.s2),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: MoshSpace.s3,
                  children: [
                    ExcludeSemantics(child: Avatar(name: peer, radius: 32)),
                    Text(status,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: MoshColors.of(context).onSurfaceVariant)),
                  ]))));

  /// The preview is the inset over remote video, else the whole stage.
  static CallVideoSurfaces _surfaces(
      BuildContext context, Size stage, bool remoteStage) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    native.Surface surface(Size size) => native.Surface(
        width: (size.width * ratio).ceil(),
        height: (size.height * ratio).ceil());
    return CallVideoSurfaces(
        local: surface(remoteStage
            ? Size(stage.width * _previewShare,
                stage.height - _previewInset(stage) * 2)
            : stage),
        remote: surface(stage));
  }

  /// How far your own camera stands from the edges of a [stage]: it keeps
  /// its share of the stage as the preview does, 8 px on a 480 px one.
  static double _previewInset(Size stage) => stage.width / 60;

  /// Your own camera over the other side's video: a quarter of the
  /// [stage]'s width, in its lower right corner.
  Widget _preview(BuildContext context, CallVideoPicture picture, String label,
          Size stage) =>
      Align(
        alignment: Alignment.bottomRight,
        child: Padding(
            padding: EdgeInsets.all(_previewInset(stage)),
            child: SizedBox(
                width: stage.width * _previewShare,
                child: AspectRatio(
                    aspectRatio: picture.aspectRatio,
                    child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                            borderRadius: _previewCorners,
                            border: Border.all(
                                color: MoshColors.of(context).outlineVariant)),
                        child: ClipRRect(
                            borderRadius: _previewCorners,
                            child:
                                _picture(picture, label, mirrored: true)))))),
      );

  Widget _picture(CallVideoPicture picture, String label,
          {required bool mirrored}) =>
      Semantics(
          // A node of its own: alone on the stage it would merge into the
          // window's.
          container: true,
          label: label,
          image: true,
          child: Transform.flip(
              flipX: mirrored,
              // A texture fills its box, so the frame's shape is kept here.
              child: Center(
                  child: AspectRatio(
                      aspectRatio: picture.aspectRatio,
                      child: Texture(textureId: picture.id)))));
}

const _previewShare = .25;
const _previewCorners = BorderRadius.all(Radius.circular(MoshRadius.small));
