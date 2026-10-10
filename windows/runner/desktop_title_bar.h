#ifndef MOSH_DESKTOP_TITLE_BAR_H_
#define MOSH_DESKTOP_TITLE_BAR_H_

#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
#include <optional>

// Only the main Dart process configures custom chrome. Native hit testing routes
// the maximize button to the top-level HWND so Windows 11 can offer Snap Layouts.
class DesktopTitleBar {
 public:
  DesktopTitleBar(HWND window, HWND view, flutter::BinaryMessenger* messenger);
  ~DesktopTitleBar();
  void SetMaximizeRegion(RECT region);
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  static LRESULT CALLBACK ViewProc(HWND, UINT, WPARAM, LPARAM, UINT_PTR, DWORD_PTR);
  int HitTest(POINT screen_point) const;
  void Hover(bool hovered);
  void ShowMenu();
  void RegisterChannel(flutter::BinaryMessenger* messenger);
  HWND window_;
  HWND view_;
  RECT maximize_region_{};
  bool hovered_ = false;
  bool pressed_ = false;
  bool configured_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
