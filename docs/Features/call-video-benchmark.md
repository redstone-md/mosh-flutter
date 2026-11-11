# Call video benchmark

What one video frame of a call costs on a machine, without a camera, a peer or
a display. It exists because the call complaints come from Macs and we own
none: CI's Apple Silicon runner measures it for us (MOSH-99). The first
measurements and what they led to are in the
[video pipeline research](../Proposals/mosh-87-video-pipeline.research.md).

```sh
node scripts/call-video-bench.mjs [--output report.md]
```

The command builds the release engine unless `MOSH_MEDIA_ENGINE` names one,
runs the three parts below and prints one Markdown table: the median ms per
frame of 60 runs after 5 warm-ups and the share of one core at 30 fps, for
640x360, 1280x720 and 1920x1080 synthetic frames.

| Part | Drives | Cases |
|------|--------|-------|
| `mosh-media/capture/src/benchmark.rs`, an ignored release test of the camera helper | the helper's converters | an NV12, a YUYV and a Motion JPEG 4:2:2 camera frame to I420 |
| `mosh-core/src/native_call/benchmark.rs`, a release test behind the `call-video-bench` feature | the engine library and the generated bridge code | the I420 encoder push, the camera preview from I420 at full and at half size, the frame copy `Hub::frame` returns, the flutter_rust_bridge encode of a frame, the copy into a main-window texture |
| `benchmark/call_video_decode.dart`, under `flutter test` | `CallVideoRenderer.decodeRgba` | the `ImageDescriptor.raw` decode |

Limits of the numbers:

- Two engines negotiate but exchange no packets, so the encoder push copies
  the frame and offers it to a sender with no connection. Codec time is not
  in the table.
- The helper rows convert a frame already in memory: the camera driver, the
  pipe to mosh-core and, on macOS, AVFoundation's own work are outside them.
  The JPEG is a synthetic picture of about a webcam frame's size (85 KiB at
  720p); mozjpeg uses its SIMD routines only where the build found nasm.
- The texture row is the copy the platform plugin makes when Rust presents a
  frame, with a stand-in for the plugin: a plain copy, and on macOS the
  Accelerate channel swap its plugin copies with. The stand-in writes to
  ordinary memory, not to the IOSurface the macOS plugin fills. On desktop
  (ADR 0052) it replaces the bridge and decode rows, which only the mobile
  frame poll still pays. The raster thread's upload is not measured.
- The bridge row is the Rust half. Dart's decode of the reply is not measured.
- flutter_tester is a JIT build with a software rasterizer. The decode row
  bounds the copy and decode work and says nothing about a GPU upload.

The `Call video benchmark` workflow runs the command on `macos-latest`,
`windows-latest` and `ubuntu-latest`, by hand or when the benchmark changes. Each table is in the
job summary and in the `call-video-bench-<os>` artifact. A change to the frame
path reports its before and after from two runs of this workflow.
