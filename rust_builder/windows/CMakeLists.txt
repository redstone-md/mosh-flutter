# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "mosh_core")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../../../../../../mosh-core mosh_core "")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
# PLUGIN_NAME in generated_plugins.cmake is normalized to "mosh_core" (underscore),
# so the bundled-libraries variable must use the underscore form to be picked up
# by Flutter's PLUGIN_BUNDLED_LIBRARIES loop. lib_name (arg 3, "mosh-core") and the
# manifest dir path keeps its hyphen (that is the cargo crate directory name),
# but lib_name (arg 3) is normalized to "mosh_core" so CARGOKIT_LIB_FULL_NAME
# (mosh_core.dll) matches cargo's cdylib output filename (cargo normalizes hyphens
# to underscores for cdylib output). The build_tool also normalizes packageName
# the same way, so both sides agree on "mosh_core.dll".
set(mosh_core_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
