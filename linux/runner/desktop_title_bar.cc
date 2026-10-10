#include "desktop_title_bar.h"

namespace {
FlValue* configuration(GtkSettings* settings) {
  gchar* layout = nullptr;
  g_object_get(settings, "gtk-decoration-layout", &layout, nullptr);
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "layout",
                          fl_value_new_string(layout ? layout : ":close"));
  g_free(layout);
  return value;
}

void preferences_changed(GtkSettings* settings, GParamSpec*, gpointer data) {
  g_autoptr(FlValue) config = configuration(settings);
  fl_method_channel_invoke_method(FL_METHOD_CHANNEL(data), "configuration",
                                 config, nullptr, nullptr, nullptr);
}

void method_called(FlMethodChannel* channel, FlMethodCall* call, gpointer data) {
  if (g_strcmp0(fl_method_call_get_name(call), "configure") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  GtkSettings* settings = gtk_widget_get_settings(GTK_WIDGET(data));
  // The channel lives with its Flutter view; changes preserve desktop button
  // placement without hard-coding GNOME's close-only layout.
  g_signal_handlers_disconnect_by_data(settings, channel);
  g_signal_connect_object(settings, "notify::gtk-decoration-layout",
                          G_CALLBACK(preferences_changed), channel,
                          static_cast<GConnectFlags>(0));
  g_autoptr(FlValue) config = configuration(settings);
  fl_method_call_respond_success(call, config, nullptr);
}
}  // namespace

void register_desktop_title_bar(FlView* view, GtkWindow* window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "mosh/window-chrome", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_called, window,
                                           nullptr);
  g_object_set_data_full(G_OBJECT(view), "mosh-desktop-title-bar", channel,
                        g_object_unref);
}
