/// Platform facts only: a foreground service is not proof of Moss reachability.
class AndroidWaitingState {
  const AndroidWaitingState({
    required this.revision,
    required this.intentRevision,
    required this.interactive,
    bool? callInteractive,
    required this.waitingEnabled,
    required this.serviceRunning,
    required this.setupComplete,
    required this.notificationsAllowed,
    required this.batteryExempt,
    required this.batteryExemptionOffered,
    this.fullScreenCallsAllowed = true,
    required this.showNamesWhenLocked,
    required this.showTextWhenLocked,
    this.restriction,
  }) : callInteractive = callInteractive ?? interactive;

  final int revision, intentRevision;
  final bool interactive, waitingEnabled, serviceRunning, setupComplete;
  final bool callInteractive;
  final bool notificationsAllowed, batteryExempt, batteryExemptionOffered;

  /// Android 14+: incoming calls may open over the lock screen.
  final bool fullScreenCallsAllowed;
  final bool showNamesWhenLocked, showTextWhenLocked;
  final String? restriction;

  factory AndroidWaitingState.fromMap(Object? value) {
    final map = value as Map<Object?, Object?>;
    return AndroidWaitingState(
      revision: map['revision'] as int,
      intentRevision: map['intentRevision'] as int,
      interactive: map['interactive'] as bool,
      callInteractive: map['callInteractive'] as bool?,
      waitingEnabled: map['waitingEnabled'] as bool,
      serviceRunning: map['serviceRunning'] as bool,
      setupComplete: map['setupComplete'] as bool,
      notificationsAllowed: map['notificationsAllowed'] as bool,
      batteryExempt: map['batteryExempt'] as bool,
      batteryExemptionOffered: map['batteryExemptionOffered'] as bool? ?? false,
      fullScreenCallsAllowed: map['fullScreenCallsAllowed'] as bool? ?? true,
      showNamesWhenLocked: map['showNamesWhenLocked'] as bool? ?? false,
      showTextWhenLocked: map['showTextWhenLocked'] as bool? ?? false,
      restriction: map['restriction'] as String?,
    );
  }
}
