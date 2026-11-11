#ifndef MOSH_CALL_VIDEO_TEXTURE_H_
#define MOSH_CALL_VIDEO_TEXTURE_H_

#include <flutter_linux/flutter_linux.h>
#include <stdint.h>

// What Rust holds for one call video texture, for as long as the process
// lives. `mosh-core/src/native_call/texture.rs` declares the same layout.
struct MoshCallVideoExport {
  // Copies a `width` by `height` RGBA frame and schedules its display. A
  // frame not shown yet is replaced. Any thread may call it.
  void (*present)(const MoshCallVideoExport* exported, const uint8_t* rgba,
                  uint32_t width, uint32_t height);
};

// Answers `textures` on "mosh/call-video" with the Flutter id and the export
// address of the call's local and remote video textures, which it registers
// on the first request and keeps.
void register_call_video(FlView* view);

#endif
