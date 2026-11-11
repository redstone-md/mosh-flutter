#ifndef MOSH_CALL_VIDEO_TEXTURE_H_
#define MOSH_CALL_VIDEO_TEXTURE_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <memory>

// Answers `textures` on "mosh/call-video" with the Flutter id and the export
// address of the call's local and remote video textures, which it registers
// on the first request. Rust keeps the exports for the life of the process;
// destroying this object, ahead of the engine, only stops their display.
class CallVideo {
 public:
  explicit CallVideo(flutter::PluginRegistrarWindows* registrar);
  ~CallVideo();

  struct Lane;

 private:
  flutter::EncodableValue Textures();
  flutter::TextureRegistrar* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  Lane* local_ = nullptr;
  Lane* remote_ = nullptr;
};

#endif
