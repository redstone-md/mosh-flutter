/// Shared session-state label mapper for the Diagnostics drawer and the
/// sessions rail, 1-в-1 with the React `stateLabels[session.state] ??
/// session.state` lookup. Maps a raw session state string to a localized
/// label via the existing `stateReady` / `stateWaiting` / `stateIdle` ARB
/// keys, falling back to the raw state string for unknown states (the same
/// `?? session.state` fallback React uses).
///
/// This is the single authoritative copy of the mapper: previously
/// `_stateLabel` was duplicated between `diagnostics_summary.dart` and
/// `sessions_screen.dart`. Both now call this shared `stateLabel`, and the
/// DiagnosticsDrawer `SessionDiagnostics` (MLS-state row) uses it too.
library;

import 'package:mosh/l10n/app_localizations.dart';

/// Maps a raw session state string to a localized label, mirroring React's
/// `stateLabels[session.state] ?? session.state`. The `connecting` state is
/// mapped to the waiting label (parity with the React `stateLabels` map,
/// which aliases connecting -> waiting).
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
