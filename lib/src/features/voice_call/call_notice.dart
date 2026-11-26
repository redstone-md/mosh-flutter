import 'package:flutter/widgets.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/shared/mosh_notice.dart';

/// What a call says above its buttons: a warning the call goes on with, or
/// the error that stopped a part of it.
class CallNotice {
  const CallNotice.warning(this.text)
      : tone = MoshNoticeTone.warning,
        icon = MoshIcons.warning;
  const CallNotice.error(this.text)
      : tone = MoshNoticeTone.error,
        icon = MoshIcons.error;

  final MoshNoticeTone tone;
  final IconData icon;
  final String text;
}
