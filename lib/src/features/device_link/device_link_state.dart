import 'package:mosh/src/rust/device_link/types.dart';

enum DeviceLinkExit { ready, linkApproved, blocked }

/// Native proof plus the lifetime of a Flutter action using that proof.
class DeviceLinkState {
  const DeviceLinkState(
      {required this.snapshot,
      this.busy = false,
      this.actionError,
      this.readError});

  final DeviceLinkSnapshot snapshot;
  final bool busy;
  final Object? actionError;
  final Object? readError;

  Object? get error => actionError ?? readError;

  bool get delivering => snapshot.phase == DeviceLinkPhase.delivering;
  bool get pending => snapshot.role != null && !idle;
  bool get connected =>
      snapshot.phase == DeviceLinkPhase.linked || snapshot.devices.length > 1;
  bool get idle =>
      snapshot.phase == DeviceLinkPhase.idle ||
      snapshot.phase == DeviceLinkPhase.failed ||
      snapshot.phase == DeviceLinkPhase.linked;

  DeviceLinkState copyWith({
    DeviceLinkSnapshot? snapshot,
    bool? busy,
    Object? actionError,
    Object? readError,
    bool clearError = false,
    bool clearReadError = false,
  }) =>
      DeviceLinkState(
          snapshot: snapshot ?? this.snapshot,
          busy: busy ?? this.busy,
          actionError: clearError ? null : actionError ?? this.actionError,
          readError: clearReadError ? null : readError ?? this.readError);
}
