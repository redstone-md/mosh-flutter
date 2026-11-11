#ifndef MOSH_CALL_VIDEO_TEXTURE_H_
#define MOSH_CALL_VIDEO_TEXTURE_H_

#include <flutter_linux/flutter_linux.h>

// Answers `textures` on "mosh/call-video" with the Flutter id and the export
// address of the call's local and remote video textures, which it registers
// on the first request and keeps.
void register_call_video(FlView* view);

#endif
