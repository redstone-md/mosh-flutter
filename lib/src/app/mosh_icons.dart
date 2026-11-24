import 'package:flutter/widgets.dart';

/// The app's icons by role: Phosphor Regular, with a filled or bold glyph
/// where the role calls for one. The fonts are bundled in `assets/fonts/`
/// (Phosphor 2.1, MIT), and each role names its glyph beside the code point.
/// `scripts/figma-design/icons.json` holds the same roles for the Figma file
/// "Mosh" (a role `done_all` there is [doneAll] here), and
/// `test/app/mosh_icons_test.dart` keeps the two lists equal.
abstract final class MoshIcons {
  static const IconData add = IconData(0xe3d4, fontFamily: 'Phosphor'); // plus
  static const IconData close = IconData(0xe4f6, fontFamily: 'Phosphor'); // x
  static const IconData download =
      IconData(0xe20c, fontFamily: 'Phosphor'); // download-simple
  static const IconData refresh =
      IconData(0xe036, fontFamily: 'Phosphor'); // arrow-clockwise
  static const IconData expandMore =
      IconData(0xe136, fontFamily: 'Phosphor'); // caret-down
  static const IconData check =
      IconData(0xe182, fontFamily: 'Phosphor'); // check
  static const IconData error =
      IconData(0xe4e2, fontFamily: 'Phosphor'); // warning-circle
  static const IconData errorFill =
      IconData(0xe4e2, fontFamily: 'PhosphorFill'); // warning-circle-fill
  static const IconData copy = IconData(0xe1ca, fontFamily: 'Phosphor'); // copy
  static const IconData group =
      IconData(0xe4d6, fontFamily: 'Phosphor'); // users
  static const IconData tag = IconData(0xe2a2, fontFamily: 'Phosphor'); // hash
  static const IconData plusBadge =
      IconData(0xe606, fontFamily: 'PhosphorFill'); // seal-check-fill
  static const IconData attach =
      IconData(0xe39a, fontFamily: 'Phosphor'); // paperclip
  static const IconData person =
      IconData(0xe4c2, fontFamily: 'Phosphor'); // user
  static const IconData doneAll =
      IconData(0xe53a, fontFamily: 'Phosphor'); // checks
  static const IconData doneAllRead =
      IconData(0xe53a, fontFamily: 'PhosphorBold'); // checks-bold
  static const IconData schedule =
      IconData(0xe19a, fontFamily: 'Phosphor'); // clock
  static const IconData call =
      IconData(0xe3b8, fontFamily: 'Phosphor'); // phone
  static const IconData callMade =
      IconData(0xe092, fontFamily: 'Phosphor'); // arrow-up-right
  static const IconData callReceived =
      IconData(0xe040, fontFamily: 'Phosphor'); // arrow-down-left
  static const IconData chat =
      IconData(0xe168, fontFamily: 'Phosphor'); // chat-circle
  static const IconData search =
      IconData(0xe30c, fontFamily: 'Phosphor'); // magnifying-glass
  static const IconData settings =
      IconData(0xe270, fontFamily: 'Phosphor'); // gear
  static const IconData play =
      IconData(0xe3d0, fontFamily: 'PhosphorFill'); // play-fill
  static const IconData pause =
      IconData(0xe39e, fontFamily: 'PhosphorFill'); // pause-fill
  static const IconData mic =
      IconData(0xe326, fontFamily: 'Phosphor'); // microphone
  static const IconData send =
      IconData(0xe396, fontFamily: 'Phosphor'); // paper-plane-right
  static const IconData delete =
      IconData(0xe4a6, fontFamily: 'Phosphor'); // trash
  static const IconData edit =
      IconData(0xe3b4, fontFamily: 'Phosphor'); // pencil-simple
  static const IconData file = IconData(0xe230, fontFamily: 'Phosphor'); // file
  static const IconData image =
      IconData(0xe2ca, fontFamily: 'Phosphor'); // image
  static const IconData organisation =
      IconData(0xe102, fontFamily: 'Phosphor'); // buildings
  static const IconData admin =
      IconData(0xe616, fontFamily: 'Phosphor'); // crown-simple
  static const IconData back =
      IconData(0xe058, fontFamily: 'Phosphor'); // arrow-left
  static const IconData more =
      IconData(0xe208, fontFamily: 'Phosphor'); // dots-three-vertical
  static const IconData listToggle =
      IconData(0xec24, fontFamily: 'Phosphor'); // sidebar-simple
  static const IconData lock =
      IconData(0xe308, fontFamily: 'Phosphor'); // lock-simple
  static const IconData info = IconData(0xe2ce, fontFamily: 'Phosphor'); // info
  static const IconData warning =
      IconData(0xe4e0, fontFamily: 'Phosphor'); // warning
  static const IconData success =
      IconData(0xe184, fontFamily: 'Phosphor'); // check-circle
  static const IconData history =
      IconData(0xe1a0, fontFamily: 'Phosphor'); // clock-counter-clockwise
  static const IconData link = IconData(0xe2e2, fontFamily: 'Phosphor'); // link
  static const IconData linkOff =
      IconData(0xe2e4, fontFamily: 'Phosphor'); // link-break
  static const IconData devices =
      IconData(0xeba4, fontFamily: 'Phosphor'); // devices
  static const IconData video =
      IconData(0xe4da, fontFamily: 'Phosphor'); // video-camera
  static const IconData minimize =
      IconData(0xe32a, fontFamily: 'Phosphor'); // minus
  static const IconData maximize =
      IconData(0xe45e, fontFamily: 'Phosphor'); // square
  static const IconData restore =
      IconData(0xe1cc, fontFamily: 'Phosphor'); // copy-simple
  static const IconData chevronRight =
      IconData(0xe13a, fontFamily: 'Phosphor'); // caret-right
  static const IconData update =
      IconData(0xe028, fontFamily: 'Phosphor'); // arrow-circle-down
  static const IconData selectAll =
      IconData(0xe746, fontFamily: 'Phosphor'); // selection-all
  static const IconData leave =
      IconData(0xe42a, fontFamily: 'Phosphor'); // sign-out
  static const IconData language =
      IconData(0xe288, fontFamily: 'Phosphor'); // globe
  static const IconData shield =
      IconData(0xe40c, fontFamily: 'Phosphor'); // shield-check
  static const IconData bug = IconData(0xe5f4, fontFamily: 'Phosphor'); // bug
  static const IconData qr =
      IconData(0xe3e6, fontFamily: 'Phosphor'); // qr-code
  static const IconData speaker =
      IconData(0xe44a, fontFamily: 'Phosphor'); // speaker-high
  static const IconData micOff =
      IconData(0xe328, fontFamily: 'Phosphor'); // microphone-slash
  static const IconData videoOff =
      IconData(0xe4dc, fontFamily: 'Phosphor'); // video-camera-slash
  static const IconData callEnd =
      IconData(0xe3bc, fontFamily: 'Phosphor'); // phone-disconnect
  static const IconData tune =
      IconData(0xe434, fontFamily: 'Phosphor'); // sliders-horizontal
  static const IconData fullscreen =
      IconData(0xe1d0, fontFamily: 'Phosphor'); // corners-out
  static const IconData fullscreenExit =
      IconData(0xe1ce, fontFamily: 'Phosphor'); // corners-in
  static const IconData callExpand =
      IconData(0xe0a6, fontFamily: 'Phosphor'); // arrows-out-simple
  static const IconData callMinimize =
      IconData(0xe09e, fontFamily: 'Phosphor'); // arrows-in-simple
  static const IconData forward =
      IconData(0xe06c, fontFamily: 'Phosphor'); // arrow-right
  static const IconData wallet =
      IconData(0xe68a, fontFamily: 'Phosphor'); // wallet
  static const IconData imageBroken =
      IconData(0xe7a8, fontFamily: 'Phosphor'); // image-broken
  static const IconData callMissed =
      IconData(0xe3c4, fontFamily: 'Phosphor'); // phone-x
  static const IconData chats =
      IconData(0xe17e, fontFamily: 'Phosphor'); // chats-circle
  static const IconData connection =
      IconData(0xeb5a, fontFamily: 'Phosphor'); // plugs-connected
  static const IconData folder =
      IconData(0xe256, fontFamily: 'Phosphor'); // folder-open
  static const IconData network =
      IconData(0xedde, fontFamily: 'Phosphor'); // network
  static const IconData lockOpen =
      IconData(0xe30a, fontFamily: 'Phosphor'); // lock-simple-open
  static const IconData moreHorizontal =
      IconData(0xe1fe, fontFamily: 'Phosphor'); // dots-three
  static const IconData notifications =
      IconData(0xe5e8, fontFamily: 'Phosphor'); // bell-ringing
  static const IconData openExternal =
      IconData(0xe5de, fontFamily: 'Phosphor'); // arrow-square-out
  static const IconData playCircle =
      IconData(0xe3d2, fontFamily: 'PhosphorFill'); // play-circle-fill
  static const IconData shieldWarning =
      IconData(0xe412, fontFamily: 'Phosphor'); // shield-warning
  static const IconData share =
      IconData(0xe408, fontFamily: 'Phosphor'); // share-network
  static const IconData chart =
      IconData(0xe154, fontFamily: 'Phosphor'); // chart-line
  static const IconData stop =
      IconData(0xe46c, fontFamily: 'PhosphorFill'); // stop-fill
  static const IconData text =
      IconData(0xe6ee, fontFamily: 'Phosphor'); // text-aa
  static const IconData plus =
      IconData(0xe606, fontFamily: 'Phosphor'); // seal-check
  static const IconData scan = IconData(0xebb6, fontFamily: 'Phosphor'); // scan
}
