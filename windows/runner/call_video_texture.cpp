#include "call_video_texture.h"

#include <flutter/standard_method_codec.h>
#include <mutex>

#include "call_video_frames.h"

namespace {
struct Export {
  MoshCallVideoExport base;
  CallVideo::Lane* lane;
};
}  // namespace

// One texture and what Rust holds of it. Never freed: Rust keeps the
// export's address.
struct CallVideo::Lane {
  explicit Lane(flutter::TextureRegistrar* textures)
      : registrar(textures),
        texture(flutter::PixelBufferTexture(
            [this](size_t, size_t) { return Copy(); })),
        id(textures->RegisterTexture(&texture)) {}

  static void Present(const MoshCallVideoExport* exported, const uint8_t* rgba,
                      uint32_t width, uint32_t height) {
    Lane* lane = reinterpret_cast<const Export*>(exported)->lane;
    lane->frames.Write(rgba, width, height);
    std::lock_guard<std::mutex> lock(lane->mutex);
    if (lane->registrar) lane->registrar->MarkTextureFrameAvailable(lane->id);
  }

  // The engine reads the buffer until its next request.
  const FlutterDesktopPixelBuffer* Copy() {
    const CallVideoFrames::Frame* frame = frames.Latest();
    if (frame == nullptr) return nullptr;
    buffer.buffer = frame->pixels.data();
    buffer.width = frame->width;
    buffer.height = frame->height;
    return &buffer;
  }

  void Close() {
    std::lock_guard<std::mutex> lock(mutex);
    registrar = nullptr;
  }

  // `[texture id, export address]`.
  flutter::EncodableValue Handle() {
    return flutter::EncodableList{
        flutter::EncodableValue(id),
        flutter::EncodableValue(
            static_cast<int64_t>(reinterpret_cast<intptr_t>(&exported)))};
  }

  Export exported{{Present}, this};
  CallVideoFrames frames;
  FlutterDesktopPixelBuffer buffer{};
  // Guards the registrar, which goes with the engine while Rust may still
  // present.
  std::mutex mutex;
  flutter::TextureRegistrar* registrar;
  flutter::TextureVariant texture;
  const int64_t id;
};

CallVideo::CallVideo(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar->texture_registrar()),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "mosh/call-video",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "textures") {
      result->Success(Textures());
    } else {
      result->NotImplemented();
    }
  });
}

CallVideo::~CallVideo() {
  channel_->SetMethodCallHandler(nullptr);
  if (local_) local_->Close();
  if (remote_) remote_->Close();
}

flutter::EncodableValue CallVideo::Textures() {
  if (!local_) {
    local_ = new Lane(registrar_);
    remote_ = new Lane(registrar_);
  }
  return flutter::EncodableMap{
      {flutter::EncodableValue("local"), local_->Handle()},
      {flutter::EncodableValue("remote"), remote_->Handle()}};
}
