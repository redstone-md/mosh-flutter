get_filename_component(MOSH_PLUGIN_ROOT "${CMAKE_CURRENT_LIST_DIR}" REALPATH)
get_filename_component(MOSH_SOURCE_ROOT "${MOSH_PLUGIN_ROOT}/.." REALPATH)
find_program(MOSH_NODE_EXECUTABLE node)
if(NOT MOSH_NODE_EXECUTABLE)
  message(FATAL_ERROR "Node.js is required to prepare native call media")
endif()
set(MOSH_NATIVE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/native_media/$<CONFIG>")
if(WIN32)
  set(MOSH_NATIVE_ENGINE "${MOSH_NATIVE_DIRECTORY}/mosh_native_media.dll")
  set(MOSH_NATIVE_CAPTURE "${MOSH_NATIVE_DIRECTORY}/mosh-camera-capture.exe")
else()
  set(MOSH_NATIVE_ENGINE "${MOSH_NATIVE_DIRECTORY}/libmosh_native_media.so")
  set(MOSH_NATIVE_CAPTURE "${MOSH_NATIVE_DIRECTORY}/mosh-camera-capture")
endif()
add_custom_target(mosh_native_media ALL
  COMMAND "${MOSH_NODE_EXECUTABLE}" "${MOSH_SOURCE_ROOT}/scripts/native-media-build.mjs"
    --profile "$<IF:$<CONFIG:Debug>,debug,release>" --output "${MOSH_NATIVE_DIRECTORY}"
  VERBATIM
)
