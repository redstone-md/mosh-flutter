import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/mosh_notice.dart';
import 'package:mosh/src/platform/desktop_window_controller.dart';
import 'call_button.dart';
import 'call_controls.dart';
import 'call_notice.dart';
import 'call_who_line.dart';

/// The three shapes the Call window card is drawn in.
enum CallWindowForm {
  desktop,

  /// A phone held upright: larger buttons, further from the bottom edge.
  upright,

  /// A phone on its side has no height to spare: the name goes beside the
  /// avatar, not under it.
  flat;

  static CallWindowForm of(BuildContext context) {
    if (!MoshControl.touch(Theme.of(context).platform)) return desktop;
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height ? flat : upright;
  }

  double get topPadding => this == desktop ? MoshSpace.s3 : MoshSpace.s2;
}

/// The main window's full screen switch, as the open call offers it.
/// [onToggle] belongs to the host, which leaves full screen with the call.
class CallFullScreen {
  const CallFullScreen({required this.window, required this.onToggle});
  final DesktopWindowController window;
  final VoidCallback onToggle;
}

/// The row along the top of the open call: the way out of it, who the call
/// is with while video has their place, and the full screen button.
class CallTopRow extends StatelessWidget {
  const CallTopRow(
      {super.key,
      required this.form,
      this.who,
      this.onMinimize,
      this.fullScreen});

  final CallWindowForm form;
  final Widget? who;
  final VoidCallback? onMinimize;
  final CallFullScreen? fullScreen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tonal = moshTonalIconButtonStyle(MoshColors.of(context));
    final full = fullScreen;
    return Padding(
      padding: EdgeInsets.all(form.topPadding),
      child: Row(spacing: MoshSpace.s2, children: [
        if (onMinimize != null)
          IconButton(
              tooltip: l.callMinimize,
              style: tonal,
              onPressed: onMinimize,
              icon: const Icon(MoshIcons.callMinimize)),
        Expanded(
            child:
                Align(alignment: AlignmentDirectional.centerStart, child: who)),
        if (full != null)
          ListenableBuilder(
              listenable: full.window,
              builder: (context, _) => IconButton(
                  tooltip: full.window.fullScreen
                      ? l.nativeMenuExitFullScreen
                      : l.nativeMenuEnterFullScreen,
                  style: tonal,
                  onPressed: full.onToggle,
                  icon: Icon(full.window.fullScreen
                      ? MoshIcons.fullscreenExit
                      : MoshIcons.fullscreen))),
      ]),
    );
  }
}

/// Who a call is with and the line about it, on a plate of their own over
/// the video, as every button has.
class CallWhoPlate extends StatelessWidget {
  const CallWhoPlate(
      {super.key,
      required this.peer,
      required this.status,
      this.statusFontFeatures,
      this.onTap});

  final String peer, status;
  final List<FontFeature>? statusFontFeatures;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoshColors.of(context);
    return MergeSemantics(
        child: Material(
      color: CallTone.neutral.plate(colors),
      shape: MoshShapes.pill,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: MoshControl.height(theme.platform),
          padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s4),
          // Centred on the plate; the row alone would hang from its top.
          child: Center(
              widthFactor: 1,
              child: CallWhoLine(
                  peer: peer,
                  line: CallLine(status, fontFeatures: statusFontFeatures))),
        ),
      ),
    ));
  }
}

/// The person of a voice call in the middle of the window: who it is and
/// how the call is going. A window too low for it scales it down.
class CallWho extends StatelessWidget {
  const CallWho(
      {super.key,
      required this.form,
      required this.peer,
      required this.status,
      this.statusFontFeatures,
      this.failed = false,
      this.onTap});

  final CallWindowForm form;
  final String peer, status;
  final List<FontFeature>? statusFontFeatures;
  final bool failed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = MoshColors.of(context);
    final flat = form == CallWindowForm.flat;
    final lines = MergeSemantics(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                flat ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            spacing: MoshSpace.s1,
            children: [
          InkWell(
              onTap: onTap,
              child: Text(peer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: form == CallWindowForm.upright
                      ? text.headlineSmall
                      : text.headlineMedium)),
          Text(status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyLarge?.copyWith(
                  color: failed ? colors.error : colors.onSurfaceVariant,
                  fontFeatures: statusFontFeatures)),
        ]));
    final avatar = ExcludeSemantics(child: Avatar(name: peer, radius: 32));
    return LayoutBuilder(
      builder: (context, box) => Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: (box.maxWidth - MoshSpace.s4 * 2)
                    .clamp(0, double.infinity)),
            child: flat
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: MoshSpace.s4,
                    children: [avatar, Flexible(child: lines)])
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: MoshSpace.s3,
                    children: [avatar, lines]),
          ),
        ),
      ),
    );
  }
}

/// The foot of the open call: its buttons on their dock and, just above
/// them, where the button it is about is, the [notice]. A [room] too low
/// for both scales them down together.
class CallFoot extends StatelessWidget {
  const CallFoot(
      {super.key,
      required this.form,
      required this.room,
      required this.controls,
      required this.onDockHover,
      this.notice});

  final CallWindowForm form;

  /// What the window has under the top row.
  final Size room;

  /// The call's buttons, drawn larger on a phone held upright.
  final List<CallControl> controls;
  final CallNotice? notice;

  /// Whether the pointer came over the dock or left it.
  final ValueChanged<bool> onDockHover;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: room.height),
        child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomCenter,
            child: SizedBox(width: room.width, child: _foot())));
  }

  Widget _foot() {
    final upright = form == CallWindowForm.upright;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          MoshSpace.s4, 0, MoshSpace.s4, upright ? MoshSpace.s8 : MoshSpace.s5),
      child: Column(spacing: MoshSpace.s3, children: [
        if (notice case final notice?)
          // As wide as its text, up to the width of a dialog.
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: IntrinsicWidth(
                  child: MoshNotice(
                      tone: notice.tone,
                      icon: notice.icon,
                      detail: notice.text,
                      // It appears mid-call, away from where the user looks.
                      announced: true,
                      radius: MoshRadius.largeIncreased))),
        MouseRegion(
            onEnter: (_) => onDockHover(true),
            onExit: (_) => onDockHover(false),
            // A window narrower than the dock scales it down.
            child: FittedBox(
                fit: BoxFit.scaleDown,
                child: CallDock(large: upright, controls: controls))),
      ]),
    );
  }
}

/// What a call left alone keeps over its video while the microphone is
/// muted: the muted button's plate, too small to be taken for a button.
class CallMutedMark extends StatelessWidget {
  const CallMutedMark({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: Padding(
        padding: EdgeInsets.all(CallWindowForm.of(context).topPadding),
        child: ExcludeSemantics(
          child: Container(
            width: MoshSpace.s8,
            height: MoshSpace.s8,
            decoration: BoxDecoration(
                color: CallTone.lit.plate(colors), shape: BoxShape.circle),
            child: Icon(MoshIcons.micOff,
                size: MoshSpace.s4, color: CallTone.lit.ink(colors)),
          ),
        ),
      ),
    );
  }
}
