import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;

/// A texture Rust feeds, showing a frame of this size.
@immutable
final class TextureVideo {
  const TextureVideo(this.id, this.width, this.height);
  final int id, width, height;

  double get aspectRatio => width / height;

  @override
  bool operator ==(Object other) =>
      other is TextureVideo &&
      other.id == id &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(id, width, height);
}

/// What each video lane shows; none while it has no live frame.
class CallVideoImages {
  const CallVideoImages({this.local, this.remote});
  final TextureVideo? local, remote;
}

/// The main window's two video textures. The platform plugin owns them and
/// Rust writes every frame into them, so this side knows only their ids and,
/// from the call snapshot, the size of the frame each one shows.
class CallVideoTextures extends ValueNotifier<CallVideoImages> {
  CallVideoTextures() : super(const CallVideoImages());

  static const channel = MethodChannel('mosh/call-video');
  ({int local, int remote})? _ids;

  /// Registers the textures on first use and hands Rust their exports. Rust
  /// refuses them before the first call is prepared, so each new call hands
  /// them over again.
  Future<void> attach(BridgeFacade bridge) async {
    final textures =
        await channel.invokeMapMethod<String, List<Object?>>('textures');
    final [localId as int, local as int] = textures!['local']!;
    final [remoteId as int, remote as int] = textures['remote']!;
    await bridge.nativeCallShowVideoIn(local: local, remote: remote);
    _ids = (local: localId, remote: remoteId);
  }

  /// Shows each lane the snapshot reports a frame for. The preview goes
  /// with the camera switch, ahead of the snapshot that confirms it.
  void show(native.Snapshot? snapshot, {required bool camera}) {
    final ids = _ids;
    TextureVideo? lane(int id, native.Surface frame) =>
        frame.width == 0 || frame.height == 0
            ? null
            : TextureVideo(id, frame.width, frame.height);
    final next = ids == null || snapshot == null
        ? const CallVideoImages()
        : CallVideoImages(
            local: camera ? lane(ids.local, snapshot.localVideo) : null,
            remote: lane(ids.remote, snapshot.remoteVideo));
    if (next.local != value.local || next.remote != value.remote) value = next;
  }
}
