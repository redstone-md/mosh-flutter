#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <cwchar>
#include <vector>

#include "../resource.h"
#include "../win32_window.h"

namespace {

std::vector<uint32_t> IconPixels(HICON icon) {
  ICONINFO info{};
  if (!icon || !GetIconInfo(icon, &info)) {
    return {};
  }
  BITMAP bitmap{};
  GetObjectW(info.hbmColor, sizeof(bitmap), &bitmap);
  std::vector<uint32_t> pixels;
  if (bitmap.bmWidth > 0 && bitmap.bmHeight > 0) {
    pixels.resize(2 + static_cast<size_t>(bitmap.bmWidth) *
                          static_cast<size_t>(bitmap.bmHeight));
    pixels[0] = static_cast<uint32_t>(bitmap.bmWidth);
    pixels[1] = static_cast<uint32_t>(bitmap.bmHeight);
    BITMAPINFO format{};
    format.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    format.bmiHeader.biWidth = bitmap.bmWidth;
    format.bmiHeader.biHeight = -bitmap.bmHeight;
    format.bmiHeader.biPlanes = 1;
    format.bmiHeader.biBitCount = 32;
    format.bmiHeader.biCompression = BI_RGB;
    HDC dc = GetDC(nullptr);
    if (GetDIBits(dc, info.hbmColor, 0, static_cast<UINT>(bitmap.bmHeight),
                  pixels.data() + 2, &format, DIB_RGB_COLORS) !=
        bitmap.bmHeight) {
      pixels.clear();
    }
    ReleaseDC(nullptr, dc);
  }
  DeleteObject(info.hbmColor);
  DeleteObject(info.hbmMask);
  return pixels;
}

}  // namespace

int main() {
  HICON expected = LoadIconW(GetModuleHandleW(nullptr),
                            MAKEINTRESOURCEW(IDI_APP_ICON));
  const auto expected_pixels = IconPixels(expected);
  if (expected_pixels.empty()) {
    std::puts("Cannot read the embedded Mosh icon.");
    return 1;
  }
  Win32Window window;
  for (int creation = 0; creation < 2; ++creation) {
    if (!window.Create(L"Mosh window icon test", {0, 0}, {100, 100})) {
      std::puts("Cannot create the runner window.");
      return 1;
    }
    wchar_t marker[2]{};
    const bool call_window = GetEnvironmentVariableW(L"MOSH_CALL_WINDOW", marker, 2) == 1 &&
                             marker[0] == L'1';
    const wchar_t* expected_class = call_window ? L"MOSH_CALL_WINDOW"
                                              : L"FLUTTER_RUNNER_WIN32_WINDOW";
    wchar_t actual_class[64]{};
    GetClassNameW(window.GetHandle(), actual_class, 64);
    if (std::wcscmp(actual_class, expected_class) != 0) {
      std::puts("The call child must not use the app-links main window class.");
      return 1;
    }
    for (WPARAM kind : {ICON_BIG, ICON_SMALL, ICON_SMALL2}) {
      HICON actual = reinterpret_cast<HICON>(
          SendMessageW(window.GetHandle(), WM_GETICON, kind, 0));
      if (IconPixels(actual) != expected_pixels) {
        std::printf("Window icon %llu differs from Mosh on creation %d.\n",
                    static_cast<unsigned long long>(kind), creation);
        return 1;
      }
    }
    window.Destroy();
  }
  std::puts("Large and small Mosh window icons survive window recreation.");
  return 0;
}
