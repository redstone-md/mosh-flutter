import 'dart:convert';
import 'dart:io';

enum SetupStep { name, device, network }

/// Local preferences only. Invitations, pairing secrets and keys stay out.
class FirstRunProfile {
  const FirstRunProfile({
    this.displayName = '',
    this.step = SetupStep.name,
    this.completed = false,
  });

  final String displayName;
  final SetupStep step;
  final bool completed;

  FirstRunProfile copyWith({
    String? displayName,
    SetupStep? step,
    bool? completed,
  }) =>
      FirstRunProfile(
        displayName: displayName ?? this.displayName,
        step: step ?? this.step,
        completed: completed ?? this.completed,
      );

  String encode() => jsonEncode({
        'version': 1,
        'displayName': displayName,
        'step': step.name,
        'completed': completed,
      });

  factory FirstRunProfile.decode(String source) {
    final value = jsonDecode(source);
    if (value
        case {
          'version': 1,
          'displayName': final String name,
          'step': final String step,
          'completed': final bool completed,
        }) {
      final steps = SetupStep.values.where((s) => s.name == step);
      if (steps.isNotEmpty &&
          name.length <= 64 &&
          (completed || step == 'name' || name.trim().isNotEmpty)) {
        return FirstRunProfile(
            displayName: name.trim(), step: steps.single, completed: completed);
      }
    }
    throw const FormatException('Invalid first-run preferences');
  }
}

/// Serialized replacement keeps a failed write from destroying saved progress.
class FirstRunStore {
  FirstRunStore(this.directory);

  final Directory? directory;
  Future<void> _writes = Future.value();

  File get _file {
    final directory = this.directory;
    if (directory == null) {
      throw StateError('Application data directory is not initialized');
    }
    return File('${directory.path}/first-run.json');
  }

  Future<FirstRunProfile?> read() async {
    final file = _file;
    if (!await file.exists()) return null;
    return FirstRunProfile.decode(await file.readAsString());
  }

  Future<void> write(FirstRunProfile profile) {
    final result = _writes.then((_) => _replace(profile));
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _replace(FirstRunProfile profile) async {
    final file = _file;
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(profile.encode(), flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
