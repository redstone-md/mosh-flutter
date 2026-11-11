#include "call_video_texture.h"

#include "call_video_frames.h"

G_DECLARE_FINAL_TYPE(MoshCallVideoTexture, mosh_call_video_texture, MOSH,
                     CALL_VIDEO_TEXTURE, FlPixelBufferTexture)

namespace {
struct Export {
  MoshCallVideoExport base;
  MoshCallVideoTexture* texture;
};
}  // namespace

struct _MoshCallVideoTexture {
  FlPixelBufferTexture parent_instance;
  Export exported;
  FlTextureRegistrar* registrar;
  CallVideoFrames* frames;
};

G_DEFINE_TYPE(MoshCallVideoTexture, mosh_call_video_texture,
              fl_pixel_buffer_texture_get_type())

namespace {
void present(const MoshCallVideoExport* exported, const uint8_t* rgba,
             uint32_t width, uint32_t height) {
  MoshCallVideoTexture* self =
      reinterpret_cast<const Export*>(exported)->texture;
  self->frames->Write(rgba, width, height);
  fl_texture_registrar_mark_texture_frame_available(self->registrar,
                                                    FL_TEXTURE(self));
}

gboolean copy_pixels(FlPixelBufferTexture* texture, const uint8_t** buffer,
                     uint32_t* width, uint32_t* height, GError** error) {
  const CallVideoFrames::Frame* frame =
      MOSH_CALL_VIDEO_TEXTURE(texture)->frames->Latest();
  if (frame == nullptr) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND,
                        "No call video frame yet");
    return FALSE;
  }
  *buffer = frame->pixels.data();
  *width = frame->width;
  *height = frame->height;
  return TRUE;
}

// One lane as `[texture id, export address]`.
FlValue* lane(FlTextureRegistrar* registrar) {
  // Never released: Rust keeps the export's address.
  MoshCallVideoTexture* texture = MOSH_CALL_VIDEO_TEXTURE(
      g_object_new(mosh_call_video_texture_get_type(), nullptr));
  texture->registrar = FL_TEXTURE_REGISTRAR(g_object_ref(registrar));
  fl_texture_registrar_register_texture(registrar, FL_TEXTURE(texture));
  FlValue* value = fl_value_new_list();
  fl_value_append_take(
      value, fl_value_new_int(fl_texture_get_id(FL_TEXTURE(texture))));
  fl_value_append_take(
      value, fl_value_new_int(reinterpret_cast<intptr_t>(&texture->exported)));
  return value;
}

void method_called(FlMethodChannel* channel, FlMethodCall* call,
                   gpointer data) {
  if (g_strcmp0(fl_method_call_get_name(call), "textures") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* textures = static_cast<FlValue*>(
      g_object_get_data(G_OBJECT(channel), "mosh-call-video-textures"));
  if (textures == nullptr) {
    FlTextureRegistrar* registrar =
        fl_engine_get_texture_registrar(fl_view_get_engine(FL_VIEW(data)));
    textures = fl_value_new_map();
    fl_value_set_string_take(textures, "local", lane(registrar));
    fl_value_set_string_take(textures, "remote", lane(registrar));
    g_object_set_data_full(G_OBJECT(channel), "mosh-call-video-textures",
                           textures,
                           reinterpret_cast<GDestroyNotify>(fl_value_unref));
  }
  fl_method_call_respond_success(call, textures, nullptr);
}
}  // namespace

static void mosh_call_video_texture_class_init(
    MoshCallVideoTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = copy_pixels;
}

static void mosh_call_video_texture_init(MoshCallVideoTexture* self) {
  self->frames = new CallVideoFrames();
  self->exported.base.present = present;
  self->exported.texture = self;
}

void register_call_video(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "mosh/call-video", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_called, view,
                                            nullptr);
  g_object_set_data_full(G_OBJECT(view), "mosh-call-video", channel,
                         g_object_unref);
}
