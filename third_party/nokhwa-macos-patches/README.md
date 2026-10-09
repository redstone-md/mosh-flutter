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

Linux runs the safe converter tests. Full Objective-C compilation, AVFoundation
permission and real camera behavior require a macOS SDK and host; a Linux
cross-target attempt stopped in the Objective-C compiler and proves neither.
The macOS CI native/build lanes exercise compilation and packaging.
