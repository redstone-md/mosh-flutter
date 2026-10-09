use crate::{Engine, frames::FrameInfo, mosh_media_probe_copy_frame, mosh_media_probe_drop};
use ringrtc::webrtc::media::{VideoFrame, VideoPixelFormat};
use std::sync::Mutex;

#[test]
fn binary_frame_abi_checks_capacity_and_copies_pixels_without_a_queue() {
    let engine = Engine::new(0).expect("real native factory");
    let frame = VideoFrame::copy_from_slice(16, 16, VideoPixelFormat::Rgba, &[70; 1024]);
    assert!(engine.endpoint.measurements.frames.store(frame));
    let handle = Box::into_raw(Box::new(Mutex::new(engine))).cast();
    let mut info = FrameInfo::default();
    // SAFETY: the test owns the handle and the aligned writable metadata;
    // zero capacity queries use no pixel allocation.
    let short =
        unsafe { mosh_media_probe_copy_frame(handle, 0, std::ptr::null_mut(), 0, &mut info) };
    assert_eq!(short, 2);
    assert_eq!(
        (info.sequence, info.width, info.height, info.rgba_bytes),
        (1, 16, 16, 1024)
    );
    let mut pixels = [0; 1024];
    // SAFETY: handle and both disjoint writable output allocations are live.
    let copied = unsafe {
        mosh_media_probe_copy_frame(handle, 0, pixels.as_mut_ptr(), pixels.len(), &mut info)
    };
    assert_eq!(copied, 1);
    assert!(pixels[0] > 50);
    assert_eq!(pixels[3], 255);
    // SAFETY: same live handle and exclusive output allocations.
    let unchanged = unsafe {
        mosh_media_probe_copy_frame(
            handle,
            info.sequence,
            pixels.as_mut_ptr(),
            pixels.len(),
            &mut info,
        )
    };
    assert_eq!(unchanged, 0);
    // SAFETY: exclusively owned handle with no concurrent operations, returned once.
    unsafe { mosh_media_probe_drop(handle) };
}

#[test]
fn binary_frame_abi_refuses_invalid_buffers_before_access() {
    let mut info = FrameInfo::default();
    // SAFETY: null handles are rejected before accessing pixel data or metadata.
    assert_eq!(
        unsafe {
            mosh_media_probe_copy_frame(std::ptr::null_mut(), 0, std::ptr::null_mut(), 0, &mut info)
        },
        -1
    );
    let engine = Engine::new(0).expect("real native factory");
    let handle = Box::into_raw(Box::new(Mutex::new(engine))).cast();
    // SAFETY: live handle; nonzero null pixels are explicitly rejected.
    assert_eq!(
        unsafe { mosh_media_probe_copy_frame(handle, 0, std::ptr::null_mut(), 1, &mut info) },
        -1
    );
    // SAFETY: live handle; oversized capacity is rejected before constructing a slice.
    assert_eq!(
        unsafe {
            mosh_media_probe_copy_frame(
                handle,
                0,
                std::ptr::null_mut(),
                crate::frames::MAX_RGBA_BYTES + 1,
                &mut info,
            )
        },
        -1
    );
    // SAFETY: live handle; null metadata is explicitly rejected.
    assert_eq!(
        unsafe {
            mosh_media_probe_copy_frame(handle, 0, std::ptr::null_mut(), 0, std::ptr::null_mut())
        },
        -1
    );
    // SAFETY: live handle and writable metadata; empty pixels do not form a null slice.
    assert_eq!(
        unsafe { mosh_media_probe_copy_frame(handle, 0, std::ptr::null_mut(), 0, &mut info) },
        0
    );
    // SAFETY: exclusively owned live handle, returned exactly once.
    unsafe { mosh_media_probe_drop(handle) };
}
