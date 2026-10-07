import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/platform/app_data_dir.dart';

/// The desktop chat list's chosen width and whether it is collapsed to its
/// avatar strip. A null [width] means the window-relative default.
@immutable
class RailLayout {
  const RailLayout({this.width, this.collapsed = false});

  final double? width;
  final bool collapsed;

  RailLayout copyWith({double? width, bool? collapsed}) => RailLayout(
      width: width ?? this.width, collapsed: collapsed ?? this.collapsed);

  @override
  bool operator ==(Object other) =>
      other is RailLayout &&
      other.width == width &&
      other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(width, collapsed);
}

final railLayoutStoreProvider = Provider<RailLayoutStore>((ref) {
  final path = appDataDir();
  return RailLayoutStore(path == null ? null : Directory(path));
});

/// UI preference only. Missing or invalid data means the default layout.
/// Atomic replacement keeps the old layout on failure; writes stay ordered.
class RailLayoutStore {
  RailLayoutStore(this.directory);
  final Directory? directory;
  Future<void> _writes = Future.value();

  File? get _file =>
      directory == null ? null : File('${directory!.path}/chat-list-layout');

  RailLayout read() {
    try {
      final json = jsonDecode(_file?.readAsStringSync() ?? '{}');
      if (json is! Map) return const RailLayout();
      final width = json['width'];
      return RailLayout(
        width: width is num && width.isFinite ? width.toDouble() : null,
        collapsed: json['collapsed'] == true,
      );
    } on FileSystemException {
      return const RailLayout();
    } on FormatException {
      return const RailLayout();
    }
  }

  Future<void> write(RailLayout layout) {
    final value =
        jsonEncode({'width': layout.width, 'collapsed': layout.collapsed});
    final result = _writes.then((_) => _write(value));
    _writes = result.then((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _write(String value) async {
    final file = _file;
    if (file == null) {
      throw StateError('Application data directory is not initialized');
    }
    await directory!.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(file.path);
  }
}

final railLayoutProvider =
    NotifierProvider<RailLayoutNotifier, RailLayout>(RailLayoutNotifier.new);

/// The chat list layout. A drag updates it live and saves once it ends;
/// a lost save only costs the choice on the next launch.
class RailLayoutNotifier extends Notifier<RailLayout> {
  @override
  RailLayout build() => ref.watch(railLayoutStoreProvider).read();

  /// Shows [layout] without saving it, for every step of a drag.
  void preview(RailLayout layout) => state = layout;

  /// Shows and saves [layout].
  Future<void> set(RailLayout layout) {
    state = layout;
    return save();
  }

  Future<void> toggle() => set(state.copyWith(collapsed: !state.collapsed));

  Future<void> save() async {
    try {
      await ref.read(railLayoutStoreProvider).write(state);
    } on Object catch (error) {
      debugPrint('Chat list layout not saved: $error');
    }
  }
}
