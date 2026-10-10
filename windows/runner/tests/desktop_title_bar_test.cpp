#include "../desktop_title_bar.h"
#include <windowsx.h>
#include <cstdio>
#include <memory>

namespace {
DesktopTitleBar* chrome = nullptr;
LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
  if (chrome) {
    if (const auto result = chrome->HandleMessage(message, wp, lp)) return *result;
  }
  return DefWindowProcW(hwnd, message, wp, lp);
}

LPARAM Position(HWND view, int x, int y) {
  POINT point{x, y};
  ClientToScreen(view, &point);
  return MAKELPARAM(point.x, point.y);
}

bool Check(HWND parent, HWND view) {
  const LPARAM button = Position(view, 170, 25);
  // The unconfigured call child keeps ordinary client mouse input.
  if (SendMessageW(parent, WM_NCHITTEST, 0, button) == HTMAXBUTTON) return false;
  chrome->SetMaximizeRegion({150, 0, 196, 44});
  if (SendMessageW(parent, WM_NCHITTEST, 0, button) != HTMAXBUTTON) return false;
  if (SendMessageW(view, WM_NCHITTEST, 0, button) != HTTRANSPARENT) return false;
  if (SendMessageW(parent, WM_NCHITTEST, 0, Position(view, 100, 2)) != HTTOP) return false;
  // A resize of another dimension must not discard unchanged caption geometry.
  SendMessageW(parent, WM_SIZE, SIZE_RESTORED, MAKELPARAM(200, 300));
  if (SendMessageW(parent, WM_NCHITTEST, 0, button) != HTMAXBUTTON) return false;
  // Moving the rendered button (including DPI changes) replaces the old region.
  chrome->SetMaximizeRegion({225, 0, 294, 66});
  if (SendMessageW(parent, WM_NCHITTEST, 0, Position(view, 260, 36)) != HTMAXBUTTON) return false;
  if (SendMessageW(parent, WM_NCHITTEST, 0, button) == HTMAXBUTTON) return false;
  chrome->SetMaximizeRegion({});
  return SendMessageW(parent, WM_NCHITTEST, 0, Position(view, 260, 36)) != HTMAXBUTTON;
}
}  // namespace

int main() {
  WNDCLASSW cls{};
  cls.lpfnWndProc = WindowProc;
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpszClassName = L"MoshCaptionTest";
  RegisterClassW(&cls);
  HWND parent = CreateWindowW(cls.lpszClassName, L"Caption test", WS_OVERLAPPEDWINDOW,
                              0, 0, 500, 400, nullptr, nullptr, cls.hInstance, nullptr);
  HWND view = CreateWindowW(L"STATIC", L"Flutter view", WS_CHILD | WS_VISIBLE,
                            0, 0, 400, 300, parent, nullptr, cls.hInstance, nullptr);
  if (!parent || !view) return 1;
  auto owner = std::make_unique<DesktopTitleBar>(parent, view, nullptr);
  chrome = owner.get();
  const bool passed = Check(parent, view);
  chrome = nullptr;
  owner.reset();
  DestroyWindow(parent);
  std::puts(passed ? "PASS native caption routing, resize and geometry updates"
                   : "FAIL native caption routing");
  return passed ? 0 : 1;
}
