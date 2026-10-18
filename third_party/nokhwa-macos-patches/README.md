# Pinned nokhwa macOS binding

The native camera preparer reconstructs nokhwa-bindings-macos 0.2.4 from its
verified official archive and applies this complete Apache-2.0 patch.

It requests BGRA only when AVFoundation advertises that output. The callback
checks the actual nonplanar CVPixelBuffer format, dimensions, row stride, data
length, pointer and lock result, then copies packed RGB without row padding.
Its bounded channel carries that actual buffer metadata and capture timestamp.
The safe packed-BGRA converter has host-independent tests for padded rows and
invalid layouts.

The callback borrows the sender owned by its retained Arc; it never constructs
an owning Arc from Arc::as_ptr. Teardown first removes the delegate, then drains
its serial queue before releasing Objective-C delegate/queue and sender owner.
This includes failures during stream initialization.

Configuration matches resolution, nokhwa's pixel-format descriptor and a native FPS
endpoint as one selection. It uses the endpoint's original boxed CMTime, so
fractional FPS is not reconstructed from the integer capability. A later
same-resolution format cannot overwrite that selection. The configuration lock
records successful acquisition and is released after applying the format and
both durations. Diagnostics list the first 64 native modes and their real FPS
ranges, followed by the selected descriptor and native timing endpoint.
The existing descriptor conversion groups some native FourCC values; diagnostics
retain each native FourCC, and duration selection stays within that exact format.

Linux runs the safe converter tests. Full Objective-C compilation, AVFoundation
permission and real camera behavior require a macOS SDK and host; a Linux
cross-target attempt stopped in the Objective-C compiler and proves neither.
The macOS CI native/build lanes exercise compilation and packaging.
