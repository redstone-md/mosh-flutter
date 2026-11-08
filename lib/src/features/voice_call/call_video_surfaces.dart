import 'package:flutter/widgets.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;

/// The device pixels each video lane fills. Rust sends frames at most at
/// these sizes, so every lane arrives no larger than it is shown.
@immutable
class CallVideoSurfaces {
  const CallVideoSurfaces({required this.local, required this.remote});
  final native.Surface local, remote;

  /// Per lane, the larger of both: enough pixels for either stage.
  CallVideoSurfaces cover(CallVideoSurfaces other) => CallVideoSurfaces(
      local: _larger(local, other.local),
      remote: _larger(remote, other.remote));

  static native.Surface _larger(native.Surface a, native.Surface b) =>
      native.Surface(
          width: a.width > b.width ? a.width : b.width,
          height: a.height > b.height ? a.height : b.height);

  Map<String, Object?> toMap() => {
        'local': [local.width, local.height],
        'remote': [remote.width, remote.height],
      };

  /// Rejects anything but two non-negative sizes within a 16K display.
  static CallVideoSurfaces fromMap(Map<Object?, Object?> map) {
    native.Surface lane(Object? value) => switch (value) {
          [int width, int height]
              when width >= 0 &&
                  height >= 0 &&
                  width <= 16384 &&
                  height <= 16384 =>
            native.Surface(width: width, height: height),
          _ => throw const FormatException('Invalid video surface'),
        };
    return CallVideoSurfaces(
        local: lane(map['local']), remote: lane(map['remote']));
  }

  @override
  bool operator ==(Object other) =>
      other is CallVideoSurfaces &&
      other.local == local &&
      other.remote == remote;

  @override
  int get hashCode => Object.hash(local, remote);
}

/// Collects the surfaces of every video stage mounted below it, offstage
/// ones included, and reports what covers them all once a frame changes it.
class CallVideoSurfaceScope extends StatefulWidget {
  const CallVideoSurfaceScope(
      {super.key, required this.onSurfaces, required this.child});
  final void Function(CallVideoSurfaces) onSurfaces;
  final Widget child;

  @override
  State<CallVideoSurfaceScope> createState() => _CallVideoSurfaceScopeState();
}

class _CallVideoSurfaceScopeState extends State<CallVideoSurfaceScope> {
  final _stages = <State, CallVideoSurfaces>{};
  CallVideoSurfaces? _reported;
  bool _scheduled = false;

  void _set(State stage, CallVideoSurfaces? surfaces) {
    if (surfaces == null) {
      _stages.remove(stage);
    } else {
      _stages[stage] = surfaces;
    }
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _stages.isEmpty) return;
      final covering = _stages.values.reduce((a, b) => a.cover(b));
      if (covering == _reported) return;
      _reported = covering;
      widget.onSurfaces(covering);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One stage's surfaces, registered with the nearest [CallVideoSurfaceScope]
/// while it is mounted.
class CallVideoSurfaceReport extends StatefulWidget {
  const CallVideoSurfaceReport(this.surfaces, {super.key, required this.child});
  final CallVideoSurfaces surfaces;
  final Widget child;

  @override
  State<CallVideoSurfaceReport> createState() => _CallVideoSurfaceReportState();
}

class _CallVideoSurfaceReportState extends State<CallVideoSurfaceReport> {
  _CallVideoSurfaceScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope =
        context.findAncestorStateOfType<_CallVideoSurfaceScopeState>();
    if (identical(scope, _scope)) return;
    _scope?._set(this, null);
    _scope = scope?.._set(this, widget.surfaces);
  }

  @override
  void didUpdateWidget(CallVideoSurfaceReport old) {
    super.didUpdateWidget(old);
    if (old.surfaces != widget.surfaces) _scope?._set(this, widget.surfaces);
  }

  @override
  void dispose() {
    _scope?._set(this, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
