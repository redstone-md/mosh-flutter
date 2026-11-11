#ifndef MOSH_CALL_VIDEO_FRAMES_H_
#define MOSH_CALL_VIDEO_FRAMES_H_

#include <cstddef>
#include <cstdint>
#include <mutex>
#include <utility>
#include <vector>

// What Rust holds for one call video texture, for as long as the process
// lives. `mosh-core/src/native_call/texture.rs` declares the same layout.
struct MoshCallVideoExport {
  // Copies a `width` by `height` RGBA frame and schedules its display. A
  // frame not shown yet is replaced. Any thread may call it.
  void (*present)(const MoshCallVideoExport* exported, const uint8_t* rgba,
                  uint32_t width, uint32_t height);
};

// The frames behind a pixel-buffer texture of the Linux and Windows runners:
// the one Rust writes next and the one the engine reads.
class CallVideoFrames {
 public:
  struct Frame {
    std::vector<uint8_t> pixels;
    uint32_t width = 0, height = 0;
  };

  // Keeps a copy of the frame, replacing one not shown yet. Any thread.
  void Write(const uint8_t* rgba, uint32_t width, uint32_t height) {
    const size_t bytes = static_cast<size_t>(width) * height * 4;
    if (bytes == 0) return;
    std::lock_guard<std::mutex> lock(mutex_);
    incoming_.pixels.assign(rgba, rgba + bytes);
    incoming_.width = width;
    incoming_.height = height;
    fresh_ = true;
  }

  // The latest frame, or null before the first. The raster thread reads it
  // from one call to the next, so only this call swaps the two.
  const Frame* Latest() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (fresh_) std::swap(incoming_, shown_);
      fresh_ = false;
    }
    return shown_.pixels.empty() ? nullptr : &shown_;
  }

 private:
  std::mutex mutex_;
  Frame incoming_, shown_;
  bool fresh_ = false;
};

#endif
