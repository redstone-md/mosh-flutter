# cmake-rs sets the target processor; the NDK also requires its ABI explicitly.
set(ANDROID_ABI arm64-v8a CACHE STRING "Mosh's supported Android ABI" FORCE)
set(ANDROID_PLATFORM android-26 CACHE STRING "Mosh's minimum Android API" FORCE)
include("$ENV{ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake")
