import 'package:mosh/l10n/app_localizations.dart';

/// Maps a raw session state string to a localized label, with the raw
/// state as the fallback for unknown states. The `connecting` state is
/// mapped to the waiting label.
String stateLabel(AppLocalizations l, String state) {
  switch (state) {
    case 'idle':
      return l.stateIdle;
    case 'waiting':
    case 'connecting':
      return l.stateWaiting;
    case 'ready':
      return l.stateReady;
    default:
      return state;
  }
}
