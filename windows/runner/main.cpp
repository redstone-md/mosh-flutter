#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

// S2-3: app_links Windows C API. `SendAppLinkToInstance()` (declared here)
// forwards a `mosh://` cold-start launch arg to an already-running instance
// of mosh.exe so only one window ever opens. Header ships with the
// app_links 7.2.1 plugin (windows/include/app_links/app_links_plugin_c_api.h)
// and is on the runner's include path via the plugin's CMakeLists.
#include "app_links/app_links_plugin_c_api.h"

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // S2-3: deep-link cold-start handoff. If a `mosh://` link launched a
  // SECOND instance of mosh.exe, the OS passed the URI as a launch arg.
  // Forward that link to the ALREADY-RUNNING instance (WM_COPYDATA), bring
  // it to the foreground, and exit this duplicate launcher. Only when NO
  // existing instance is found does this instance create its window as
  // usual. Must run before AttachConsole / CoInitializeEx / window creation
  // so the duplicate never opens a console or a second window.
  // (app_links 7.2.1, windows/include/app_links/app_links_plugin_c_api.h.)
  if (SendAppLinkToInstance()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM *and* OLE (single-threaded apartment). super_clipboard /
  // super_native_extensions read the clipboard through `OleGetClipboard` and
  // register drop targets with `RegisterDragDrop`; both need OleInitialize,
  // and a plain CoInitializeEx made every Ctrl+V fail (see the plugin's own
  // runner and its warning in win32/drop.rs).
  ::OleInitialize(nullptr);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"mosh", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::OleUninitialize();
  return EXIT_SUCCESS;
}
