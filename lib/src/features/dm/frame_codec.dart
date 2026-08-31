// Migration shim -- the call pipeline moved to its own feature module.
//
// `frame_codec.dart` now lives in `lib/src/features/voice_call/`. This file only
// re-exports it, so every existing importer keeps compiling untouched.
//
// Transitional: point new imports at `features/voice_call/` directly, and
// delete this shim once nothing outside `features/dm/` imports it.

library;

export 'package:mosh/src/features/voice_call/frame_codec.dart';
