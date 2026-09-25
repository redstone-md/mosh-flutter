/// How a DM's proven state and transport read on screen.
///
/// The runtime reports three states: nobody has joined yet, the contact is
/// not reachable right now, or the contact has answered. The header, the
/// rail badge, the title-bar pill and the diagnostics card all say the same
/// thing about the same state, so the wording lives here once.
library;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show DmSessionState;
import 'package:mosh/src/rust/private_dm_runtime/transport.dart'
    show PeerTransport;

/// The short label: a rail badge, a state pill, a diagnostics row.
String dmStateLabel(AppLocalizations l, DmSessionState state) =>
    switch (state) {
      DmSessionState.pending => l.dmStateWaiting,
      DmSessionState.handshaking => l.stateOffline,
      DmSessionState.connected => l.stateReady,
    };

/// The full sentence the chat header shows. Connected names the transport
/// next to it, so the reader knows why a chat may be slower. A connected
/// contact with no direct or relayed path still talks: gossip carries the
/// chat through other peers, so the sentence says that instead of "no path".
String dmStateSentence(
  AppLocalizations l,
  DmSessionState state,
  PeerTransport transport,
) =>
    switch (state) {
      DmSessionState.pending => l.dmStateWaiting,
      DmSessionState.handshaking => l.stateOfflineSentence,
      DmSessionState.connected =>
        '${l.stateReady} · ${_connectedVia(l, transport)}',
    };

String _connectedVia(AppLocalizations l, PeerTransport transport) =>
    transport == PeerTransport.none
        ? l.transportMesh
        : transportLabel(l, transport);

String transportLabel(AppLocalizations l, PeerTransport transport) =>
    switch (transport) {
      PeerTransport.direct => l.transportDirect,
      PeerTransport.relayed => l.transportRelayed,
      PeerTransport.none => l.transportNone,
    };

/// The pill tone the shared chrome understands: `ready` for a proven
/// connection, `waiting` for either state short of it.
String dmPillState(DmSessionState state) =>
    state == DmSessionState.connected ? 'ready' : 'waiting';
