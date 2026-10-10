#include "desktop_title_bar.h"

#include <commctrl.h>
#include <windowsx.h>
#include <flutter/standard_method_codec.h>
#include <cmath>

namespace {
POINT ScreenPoint(LPARAM value) {
  return {GET_X_LPARAM(value), GET_Y_LPARAM(value)};
}

double Number(const flutter::EncodableMap& map, const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return 0;
  if (const auto value = std::get_if<double>(&it->second)) return *value;
  if (const auto value = std::get_if<int32_t>(&it->second)) return *value;
  return 0;
}

RECT Bounds(const flutter::EncodableMap& map, double ratio) {
  return {static_cast<LONG>(std::lround(Number(map, "left") * ratio)),
          static_cast<LONG>(std::lround(Number(map, "top") * ratio)),
          static_cast<LONG>(std::lround(Number(map, "right") * ratio)),
          static_cast<LONG>(std::lround(Number(map, "bottom") * ratio))};
}
}  // namespace

DesktopTitleBar::DesktopTitleBar(HWND window, HWND view,
                               flutter::BinaryMessenger* messenger)
    : window_(window), view_(view) {
  SetWindowSubclass(view_, ViewProc, reinterpret_cast<UINT_PTR>(this),
                    reinterpret_cast<DWORD_PTR>(this));
  if (messenger) RegisterChannel(messenger);
}

DesktopTitleBar::~DesktopTitleBar() {
  RemoveWindowSubclass(view_, ViewProc, reinterpret_cast<UINT_PTR>(this));
  if (channel_) channel_->SetMethodCallHandler(nullptr);
}

void DesktopTitleBar::SetMaximizeRegion(RECT region, RECT buttons) {
  configured_ = true;
  maximize_region_ = region;
  buttons_region_ = buttons;
}

void DesktopTitleBar::RegisterChannel(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "mosh/window-chrome", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "configure") {
      configured_ = true;
      result->Success(flutter::EncodableValue(flutter::EncodableMap{}));
    } else if (call.method_name() == "maximizeRegion") {
      const auto* args = call.arguments()
          ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
      if (!args) { result->Error("invalid-region", "Expected caption rectangle"); return; }
      const double ratio = Number(*args, "pixelRatio");
      RECT buttons{};
      const auto it = args->find(flutter::EncodableValue("buttons"));
      if (it != args->end()) {
        if (const auto* map = std::get_if<flutter::EncodableMap>(&it->second)) {
          buttons = Bounds(*map, ratio);
        }
      }
      SetMaximizeRegion(Bounds(*args, ratio), buttons);
      result->Success();
    } else if (call.method_name() == "showMenu") {
      ShowMenu();
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
}

int DesktopTitleBar::HitTest(POINT point) const {
  if (!configured_) return HTCLIENT;
  ScreenToClient(view_, &point);
  if (PtInRect(&maximize_region_, point)) return HTMAXBUTTON;
  if (PtInRect(&buttons_region_, point)) return HTCLIENT;
  const UINT dpi = GetDpiForWindow(window_);
  const int padding = GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const int border_x = GetSystemMetricsForDpi(SM_CXFRAME, dpi) + padding;
  const int border_y = GetSystemMetricsForDpi(SM_CYFRAME, dpi) + padding;
  if (!IsZoomed(window_) && (GetWindowLongPtr(window_, GWL_STYLE) & WS_THICKFRAME) &&
      point.y >= 0 && point.y < border_y) {
    RECT client;
    GetClientRect(view_, &client);
    if (point.x < border_x) return HTTOPLEFT;
    if (point.x >= client.right - border_x) return HTTOPRIGHT;
    return HTTOP;
  }
  return HTCLIENT;
}

LRESULT CALLBACK DesktopTitleBar::ViewProc(HWND hwnd, UINT message, WPARAM wparam,
                                          LPARAM lparam, UINT_PTR, DWORD_PTR data) {
  auto* owner = reinterpret_cast<DesktopTitleBar*>(data);
  if (message == WM_NCHITTEST && owner->HitTest(ScreenPoint(lparam)) != HTCLIENT) {
    // Flutter and the parent HWND share the UI thread. Pass these caption and
    // resize hits through the view to the native top-level window.
    return HTTRANSPARENT;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

void DesktopTitleBar::Hover(bool hovered) {
  if (hovered_ == hovered) return;
  hovered_ = hovered;
  if (channel_) channel_->InvokeMethod("maximizeHover",
      std::make_unique<flutter::EncodableValue>(hovered));
}

std::optional<LRESULT> DesktopTitleBar::HandleMessage(UINT message, WPARAM wparam,
                                                     LPARAM lparam) {
  if (!configured_) return std::nullopt;
  switch (message) {
    case WM_NCHITTEST: {
      const int hit = HitTest(ScreenPoint(lparam));
      if (hit != HTCLIENT) return hit;
      break;
    }
    case WM_NCMOUSEMOVE: {
      Hover(wparam == HTMAXBUTTON);
      TRACKMOUSEEVENT tracking{sizeof(TRACKMOUSEEVENT), TME_LEAVE | TME_NONCLIENT,
                               window_, 0};
      TrackMouseEvent(&tracking);
      break;
    }
    case WM_NCMOUSELEAVE:
      Hover(false);
      break;
    case WM_NCLBUTTONDOWN:
      if (wparam == HTMAXBUTTON) {
        pressed_ = true;
        SetCapture(window_);
        return 0;
      }
      break;
    case WM_LBUTTONUP:
      if (pressed_) {
        POINT point = ScreenPoint(lparam);
        ClientToScreen(window_, &point);
        const bool activate = HitTest(point) == HTMAXBUTTON;
        pressed_ = false;
        ReleaseCapture();
        if (activate) PostMessage(window_, WM_SYSCOMMAND,
                                  IsZoomed(window_) ? SC_RESTORE : SC_MAXIMIZE, 0);
        return 0;
      }
      break;
    case WM_CAPTURECHANGED:
      pressed_ = false;
      break;
    case WM_DPICHANGED:
      SetMaximizeRegion({});
      [[fallthrough]];
    case WM_SIZE:
    case WM_KILLFOCUS:
      Hover(false);
      break;
  }
  return std::nullopt;
}

void DesktopTitleBar::ShowMenu() {
  POINT point;
  GetCursorPos(&point);
  HMENU menu = GetSystemMenu(window_, FALSE);
  EnableMenuItem(menu, SC_RESTORE, MF_BYCOMMAND | (IsZoomed(window_) ? MF_ENABLED : MF_GRAYED));
  EnableMenuItem(menu, SC_MAXIMIZE, MF_BYCOMMAND | (IsZoomed(window_) ? MF_GRAYED : MF_ENABLED));
  const UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
                                      point.x, point.y, 0, window_, nullptr);
  if (command) PostMessage(window_, WM_SYSCOMMAND, command, 0);
}
