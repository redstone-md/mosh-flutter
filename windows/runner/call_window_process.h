#ifndef RUNNER_CALL_WINDOW_PROCESS_H_
#define RUNNER_CALL_WINDOW_PROCESS_H_

#include <windows.h>

namespace mosh {

inline bool IsCallWindowProcess() {
  wchar_t marker[2]{};
  return GetEnvironmentVariableW(L"MOSH_CALL_WINDOW", marker, 2) == 1 &&
         marker[0] == L'1';
}

// app_links discovers only the main runner class. Freeze the choice for this
// process so registration, creation and unregister always use the same name.
inline const wchar_t* WindowClassName() {
  static const bool call_window = IsCallWindowProcess();
  return call_window ? L"MOSH_CALL_WINDOW" : L"FLUTTER_RUNNER_WIN32_WINDOW";
}

}  // namespace mosh

#endif  // RUNNER_CALL_WINDOW_PROCESS_H_
