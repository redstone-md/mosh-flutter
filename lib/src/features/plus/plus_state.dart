import 'package:mosh/src/rust/plus/types.dart';

class PlusState {
  const PlusState({required this.snapshot, this.busy = false, this.error});
  final PlusSnapshot snapshot;
  final bool busy;
  final Object? error;
}
