// File names of the packaged engine library and camera helper on this host.
export const engineLibrary = process.platform === "win32" ? "mosh_native_media.dll"
  : process.platform === "darwin" ? "libmosh_native_media.dylib" : "libmosh_native_media.so";
export const cameraHelper = process.platform === "win32" ? "mosh-camera-capture.exe" : "mosh-camera-capture";
