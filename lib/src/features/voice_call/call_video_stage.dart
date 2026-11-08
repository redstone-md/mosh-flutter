import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;

import 'call_video_renderer.dart';
import 'call_video_surfaces.dart';

/// Presentation only. Pixel changes never animate; stage presence may fade.
class CallVideoStage extends StatelessWidget {
  const CallVideoStage(
      {super.key,
      required this.images,
      required this.peer,
      this.inset = true,
      this.alwaysVisible = false,
      this.remoteCamera = false});
  final ValueListenable<CallVideoImages> images;
  final String peer;
  final bool remoteCamera;
  final bool inset;
  final bool alwaysVisible;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CallVideoImages>(
        valueListenable: images,
        builder: (context, images, _) => AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          child: !alwaysVisible &&
                  !remoteCamera &&
                  images.remote == null &&
                  images.local == null
              ? const SizedBox.shrink(key: ValueKey(false))
              : _stage(context, images),
        ),
      );

  Widget _stage(BuildContext context, CallVideoImages images) {
    final remoteStage = remoteCamera || images.remote != null;
    return Padding(
      key: const ValueKey(true),
      padding: EdgeInsets.only(top: inset ? 12 : 0),
      child: AspectRatio(
          aspectRatio: 16 / 9,
          child: LayoutBuilder(
              builder: (context, box) => CallVideoSurfaceReport(
                  _surfaces(context, box.biggest, remoteStage),
                  child: RepaintBoundary(
                      child: ColoredBox(
                          color: MoshColors.bg0,
                          child: Stack(
                              fit: StackFit.expand,
                              children: _layers(context, images,
                                  remoteStage: remoteStage))))))),
    );
  }

  List<Widget> _layers(BuildContext context, CallVideoImages images,
      {required bool remoteStage}) {
    final remote = images.remote;
    final preview = images.local;
    final l = AppLocalizations.of(context)!;
    return [
      if (remote != null)
        _picture(remote, l.callRemoteVideo(peer), mirrored: false)
      else if (remoteStage)
        Center(child: Text(l.callWaitingForVideo))
      else if (preview != null)
        _picture(preview, l.callLocalPreview, mirrored: true)
      else
        Center(
            child: Semantics(
                label: peer,
                child: const Icon(Icons.person_outline, size: 32))),
      if (remoteStage && preview != null) _preview(preview, l.callLocalPreview),
    ];
  }

  /// The preview is a quarter-width inset over remote video, else the stage.
  static CallVideoSurfaces _surfaces(
      BuildContext context, Size stage, bool remoteStage) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    native.Surface surface(double width, double height) => native.Surface(
        width: (width * ratio).ceil(), height: (height * ratio).ceil());
    return CallVideoSurfaces(
        local: surface(
            stage.width * (remoteStage ? _previewShare : 1), stage.height),
        remote: surface(stage.width, stage.height));
  }

  Widget _preview(ui.Image image, String label) => Align(
        alignment: Alignment.bottomRight,
        child: Padding(
            padding: const EdgeInsets.all(8),
            child: FractionallySizedBox(
                widthFactor: _previewShare,
                child: AspectRatio(
                    aspectRatio: image.width / image.height,
                    child: _picture(image, label, mirrored: true)))),
      );

  Widget _picture(ui.Image image, String label, {required bool mirrored}) =>
      Semantics(
          label: label,
          image: true,
          child: Transform.flip(
              flipX: mirrored,
              child: RawImage(image: image, fit: BoxFit.contain)));
}

const _previewShare = .25;
