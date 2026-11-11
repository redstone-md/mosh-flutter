import Accelerate
import CoreVideo
import FlutterMacOS

/// One video texture of the main window. Rust presents each frame through
/// `exported`; the engine takes the latest as an IOSurface-backed BGRA
/// buffer, which Metal samples without a further copy.
final class CallVideoTexture: NSObject, FlutterTexture {
  private typealias Present = @convention(c) (
    UnsafeRawPointer, UnsafePointer<UInt8>, UInt32, UInt32
  ) -> Void
  private static let word = MemoryLayout<UnsafeRawPointer>.stride

  /// What Rust holds for as long as the process lives: the `present` function
  /// `mosh-core/src/native_call/texture.rs` declares, then this texture.
  let exported = UnsafeMutableRawPointer.allocate(
    byteCount: 2 * CallVideoTexture.word, alignment: MemoryLayout<UnsafeRawPointer>.alignment)
  private(set) var id: Int64 = 0
  private weak var registry: FlutterTextureRegistry?
  private let lock = NSLock()
  private var pool: CVPixelBufferPool?
  private var latest: CVPixelBuffer?

  init(registry: FlutterTextureRegistry) {
    self.registry = registry
    super.init()
    let present: Present = { exported, rgba, width, height in
      Unmanaged<CallVideoTexture>
        .fromOpaque(exported.load(fromByteOffset: CallVideoTexture.word, as: UnsafeRawPointer.self))
        .takeUnretainedValue()
        .present(rgba, width: Int(width), height: Int(height))
    }
    exported.storeBytes(of: present, as: Present.self)
    // Retained for good: Rust keeps the export's address.
    exported.storeBytes(
      of: UnsafeRawPointer(Unmanaged.passRetained(self).toOpaque()),
      toByteOffset: Self.word, as: UnsafeRawPointer.self)
    id = registry.register(self)
  }

  /// Copies a `width` by `height` RGBA frame and schedules its display. A
  /// frame not shown yet is replaced. Any thread may call it.
  func present(_ rgba: UnsafePointer<UInt8>, width: Int, height: Int) {
    guard width > 0, height > 0, let buffer = buffer(width: width, height: height),
      CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess
    else { return }
    var source = vImage_Buffer(
      data: UnsafeMutableRawPointer(mutating: rgba), height: vImagePixelCount(height),
      width: vImagePixelCount(width), rowBytes: width * 4)
    var target = vImage_Buffer(
      data: CVPixelBufferGetBaseAddress(buffer), height: vImagePixelCount(height),
      width: vImagePixelCount(width), rowBytes: CVPixelBufferGetBytesPerRow(buffer))
    let bgra: [UInt8] = [2, 1, 0, 3]
    let written = vImagePermuteChannels_ARGB8888(
      &source, &target, bgra, vImage_Flags(kvImageNoFlags))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    guard written == kvImageNoError else { return }
    lock.lock()
    latest = buffer
    lock.unlock()
    registry?.textureFrameAvailable(id)
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    return latest.map { Unmanaged.passRetained($0) }
  }

  /// A buffer of the pool to write the next frame into. The pool recycles
  /// one once the engine and `latest` have let go of it.
  private func buffer(width: Int, height: Int) -> CVPixelBuffer? {
    lock.lock()
    defer { lock.unlock() }
    if let shown = latest,
      CVPixelBufferGetWidth(shown) != width || CVPixelBufferGetHeight(shown) != height
    {
      pool = nil
    }
    if pool == nil {
      let attributes: [CFString: Any] = [
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey: width,
        kCVPixelBufferHeightKey: height,
        kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
        kCVPixelBufferMetalCompatibilityKey: true,
      ]
      CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
    }
    var buffer: CVPixelBuffer?
    if let pool = pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) }
    return buffer
  }
}

/// Answers `textures` on "mosh/call-video" with the Flutter id and the export
/// address of the call's local and remote video textures, which it registers
/// on the first request and keeps.
final class CallVideo {
  private let channel: FlutterMethodChannel
  private var lanes: [String: [Int64]]?

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(name: "mosh/call-video", binaryMessenger: registrar.messenger)
    let registry = registrar.textures
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "textures" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let lane = { () -> [Int64] in
        let texture = CallVideoTexture(registry: registry)
        return [texture.id, Int64(Int(bitPattern: texture.exported))]
      }
      let lanes = self.lanes ?? ["local": lane(), "remote": lane()]
      self.lanes = lanes
      result(lanes)
    }
  }
}
