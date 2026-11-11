import 'dart:io' show Platform;

import 'package:media_kit/media_kit.dart';

import 'system_player.dart';

/// Whether media plays through the system's own player rather than libmpv:
/// on Android (ADR 0053).
final bool playsThroughSystem = Platform.isAndroid;

/// Makes a player for one attachment or recording; [video] when it is
/// watched rather than only heard.
typedef MediaPlayerFactory = Player Function({bool video});

/// Readies playback once, before the first player is made.
void initializeMediaPlayback() {
  if (!playsThroughSystem) MediaKit.ensureInitialized();
}

/// The platform's player. Throws where libmpv is missing, as in tests.
Player createMediaPlayer({bool video = false}) => playsThroughSystem
    ? Player(platformPlayer: SystemPlayer(video: video))
    : Player();
