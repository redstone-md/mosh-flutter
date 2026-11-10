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
| `mosh-core/src/native_call/benchmark.rs`, a release test behind the `call-video-bench` feature | the engine library and the generated bridge code | RGBA to I420 with the encoder push, I420 to RGBA, the preview's `scale_rgba`, the frame copy `Hub::frame` makes, the flutter_rust_bridge encode of a frame |
| `benchmark/call_frame_transport.dart`, compiled | `CallVideoFrame`, `CallWindowFrameChannel` and `CallWindowInput` in two processes | encode, loopback send, parse and one acknowledgement per frame |
| `benchmark/call_video_decode.dart`, under `flutter test` | `CallVideoRenderer.decodeRgba` | the `ImageDescriptor.raw` decode |

Limits of the numbers:

- Two engines negotiate but exchange no packets, so the encoder push converts
  the frame and offers it to a sender with no connection. Codec time is not
  in the table.
- The bridge row is the Rust half. Dart's decode of the reply is not measured.
- The socket row is wall time with both processes working back to back, which
  is the CPU of both ends as long as neither waits on anything else.
- flutter_tester is a JIT build with a software rasterizer. The decode row
  bounds the copy and decode work and says nothing about a GPU upload.

The `Call video benchmark` workflow runs the command on `macos-latest` and
`ubuntu-latest`, by hand or when the benchmark changes. Each table is in the
job summary and in the `call-video-bench-<os>` artifact. A change to the frame
path reports its before and after from two runs of this workflow.
