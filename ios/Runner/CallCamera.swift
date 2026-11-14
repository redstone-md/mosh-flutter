import AVFoundation
import Flutter
import UIKit

/// The call's camera on iPhone. AVFoundation delivers biplanar 4:2:0 video
/// range frames turned upright for the device's orientation; each is repacked
/// as I420 and handed to mosh-core with the generation of the capture that
/// asked for it (`mosh-core/src/native_call/capture/mobile.rs`).
final class CallCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  private typealias Frame = @convention(c) (UInt64, UInt32, UInt32, UnsafePointer<UInt8>, Int) -> Void
  private typealias Failed = @convention(c) (UInt64) -> Void

  private let frame: Frame? = CallMedia.symbol("mosh_ios_camera_frame")
  private let failed: Failed? = CallMedia.symbol("mosh_ios_camera_failed")
  /// Owns the session; frames arrive on it too.
  private let queue = DispatchQueue(label: "app.mosh.call-camera")
  private var session: AVCaptureSession?
  private var connection: AVCaptureConnection?
  private var generation: UInt64 = 0
  private var observers: [NSObjectProtocol] = []
  private var packed: [UInt8] = []

  func devices() -> [[String: Any]] {
    Self.cameras().map { ["id": $0.uniqueID, "name": $0.localizedName, "stable": true] }
  }

  func start(id: String?, generation: UInt64) {
    queue.async {
      self.release()
      self.generation = generation
      do {
        try self.open(id)
      } catch {
        self.failed?(generation)
        self.release()
      }
    }
  }

  func stop() {
    queue.async { self.release() }
  }

  /// Answers `camera` on "app.mosh/call_permissions" with whether the user
  /// lets Mosh use the camera, asking the first time.
  static func handlePermissions(_ messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
    let channel = FlutterMethodChannel(name: "app.mosh/call_permissions", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "camera" else { return result(FlutterMethodNotImplemented) }
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async { result(granted) }
      }
    }
    return channel
  }

  private static func cameras() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
    ).devices
  }

  private func open(_ id: String?) throws {
    let cameras = Self.cameras()
    let picked = id.map { id in cameras.first { $0.uniqueID == id } }
      ?? cameras.first { $0.position == .front } ?? cameras.first
    guard let device = picked else { throw CallMediaError.noCamera }
    let session = AVCaptureSession()
    session.beginConfiguration()
    // The engine sends up to 720p and scales down for the path.
    session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .vga640x480
    let input = try AVCaptureDeviceInput(device: device)
    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)
    guard session.canAddInput(input), session.canAddOutput(output) else { throw CallMediaError.noCamera }
    session.addInput(input)
    session.addOutput(output)
    connection = output.connection(with: .video)
    session.commitConfiguration()
    self.session = session
    let generation = self.generation
    observers = [
      NotificationCenter.default.addObserver(
        forName: .AVCaptureSessionRuntimeError, object: session, queue: nil
      ) { [weak self] _ in self?.failed?(generation) },
      NotificationCenter.default.addObserver(
        forName: UIDevice.orientationDidChangeNotification, object: nil, queue: nil
      ) { [weak self] _ in self?.turnUpright() },
    ]
    DispatchQueue.main.async { UIDevice.current.beginGeneratingDeviceOrientationNotifications() }
    turnUpright()
    session.startRunning()
  }

  /// Frames leave upright for how the phone is held; face up or down keeps
  /// the last orientation.
  private func turnUpright() {
    DispatchQueue.main.async {
      let orientation: AVCaptureVideoOrientation
      switch UIDevice.current.orientation {
      case .portrait: orientation = .portrait
      case .portraitUpsideDown: orientation = .portraitUpsideDown
      // The device turned left holds the camera's image turned right.
      case .landscapeLeft: orientation = .landscapeRight
      case .landscapeRight: orientation = .landscapeLeft
      default: return
      }
      self.queue.async {
        guard let connection = self.connection, connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = orientation
      }
    }
  }

  private func release() {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    if !observers.isEmpty {
      DispatchQueue.main.async { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
    }
    observers = []
    session?.stopRunning()
    session = nil
    connection = nil
    // No frame of this capture reaches mosh-core after this.
    generation = 0
  }

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
  ) {
    guard generation != 0, let frame = frame, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
      CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess
    else { return }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
    let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
    guard width % 2 == 0, height % 2 == 0,
      let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
      let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)
    else { return }
    let size = width * height * 3 / 2
    if packed.count != size { packed = [UInt8](repeating: 0, count: size) }
    let generation = self.generation
    packed.withUnsafeMutableBufferPointer { planes in
      guard let target = planes.baseAddress else { return }
      Self.pack(
        luma: luma.assumingMemoryBound(to: UInt8.self), lumaStride: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0),
        chroma: chroma.assumingMemoryBound(to: UInt8.self),
        chromaStride: CVPixelBufferGetBytesPerRowOfPlane(buffer, 1),
        width: width, height: height, into: target)
      frame(generation, UInt32(width), UInt32(height), target, size)
    }
  }

  /// I420 from NV12: the Y rows without their padding, then the interleaved
  /// CbCr plane split into U and V.
  private static func pack(
    luma: UnsafePointer<UInt8>, lumaStride: Int, chroma: UnsafePointer<UInt8>, chromaStride: Int,
    width: Int, height: Int, into target: UnsafeMutablePointer<UInt8>
  ) {
    for row in 0..<height {
      (target + row * width).update(from: luma + row * lumaStride, count: width)
    }
    let half = width / 2
    let quarter = half * (height / 2)
    let u = target + width * height
    let v = u + quarter
    for row in 0..<height / 2 {
      let source = chroma + row * chromaStride
      let offset = row * half
      for column in 0..<half {
        u[offset + column] = source[2 * column]
        v[offset + column] = source[2 * column + 1]
      }
    }
  }
}
