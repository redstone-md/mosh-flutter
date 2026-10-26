/// The native elapsed clock and durable record; no wall-clock access grants.
class AndroidAccessState {
  AndroidAccessState.fromMap(Map<Object?, Object?> value)
      : delaySeconds = value['delaySeconds'] as int,
        bootCount = value['bootCount'] as int?,
        deadlineElapsedMs = value['deadlineElapsedMs'] as int?,
        state = value['state'] as String,
        revision = value['revision'] as int,
        shieldGeneration = value['shieldGeneration'] as int,
        deviceInteractive = value['deviceInteractive'] == true,
        allowed = value['allowed'] == true {
    if (value['version'] != 1 ||
        !delays.contains(delaySeconds) ||
        !const ['locked', 'interactive', 'grace'].contains(state)) {
      throw const FormatException('Invalid access state');
    }
  }

  static const delays = [0, 60, 300, 600, 1800];
  final int delaySeconds, revision, shieldGeneration;
  final int? bootCount, deadlineElapsedMs;
  final String state;
  final bool deviceInteractive, allowed;

  Map<String, Object?> record({int? delay, String? phase}) => {
        'version': 1,
        'delaySeconds': delay ?? delaySeconds,
        'bootCount': bootCount,
        'deadlineElapsedMs': deadlineElapsedMs,
        'state': phase ?? state,
      };
}
