# Issue 47: chat names

## Agreed behavior

- Private DMs and public channels have personal names, synchronized only
  between the user's active linked devices. Reset restores the original name.
- Current group admins change the shared group name. An authenticated typed
  history event identifies the author and new name.
- Open-chat and list-row menus use one rename dialog. Names contain 1–64
  Unicode scalar values after trimming, with no controls or line breaks.
- Offline changes persist before the UI reports acceptance. Reconnect,
  restart, new devices and new group members recover current names.
- Concurrent updates converge automatically. Older clients keep messaging;
  name updates require an updated client.

## Implementation and boundaries

1. Add a native encrypted personal-name register with versioned reset
   tombstones. Use the stable DM session id and canonical channel name as keys.
2. Extend the existing device-link owner with signed, recipient-bound name
   synchronization on the encrypted directed stream. The trusted local roster
   authorizes senders and recipients. Keep a single owner of its inbox.
3. Add authenticated group metadata updates, durable pending changes and
   current-state recovery. Reuse MLS exporter-derived encryption and SenderProof;
   require actual runtime admin authority before accepting any new name.
   Custom MLS context extensions would require migrating all existing leaves,
   so they are unsuitable for this compatible change.
4. Add conversation commands and typed snapshots/events to the bridge. Use
   one Flutter name resolver for the list, search, header, details and calls,
   with a shared dialog and existing menu primitives.

## Checks and risks

Tests exercise native public methods/snapshots with real encrypted storage,
independent Moss processes for device synchronization, and Flutter menu/dialog
behavior through test/support. Cover restart, offline delivery, duplicate and
concurrent updates, reset propagation, outsiders/revoked devices, group admin
handoff and org roles. Run Flutter analyze/tests/format; Rust build/tests/fmt/
clippy; bridge generation and drift checks. Update architecture and an ADR.

Main risks are unauthorized metadata, premature delivery success, stale replay
after reset, names lost after admin departure and mixed-client compatibility.
Publication alone must never be presented as proof of peer persistence.
