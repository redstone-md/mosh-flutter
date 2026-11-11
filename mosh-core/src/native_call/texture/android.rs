//! Android's video textures. Flutter's `SurfaceProducer` hands out a
//! `Surface` whose buffer queue makes its producer wait while the platform
//! thread is busy, so each texture has a thread that writes into it; the
//! call's owner only leaves the latest frame for that thread.
use super::Exported;
use std::sync::{Condvar, Mutex, MutexGuard, PoisonError};

/// Where one texture's frames end up.
pub(crate) trait Screen: Send + 'static {
    /// Shows a `width` by `height` RGBA frame; may wait for the display.
    fn show(&mut self, width: u32, height: u32, rgba: &[u8]);
}

#[derive(Default)]
struct Frame {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
}

/// The frame the screen takes next, once it is `fresh`.
#[derive(Default)]
struct Next {
    frame: Frame,
    fresh: bool,
}

/// One texture's export and the latest frame presented to it.
#[repr(C)]
pub(crate) struct Latest {
    exported: Exported,
    next: Mutex<Next>,
    arrived: Condvar,
}

impl Latest {
    /// A texture whose frames a thread of its own shows on `screen`. Leaked,
    /// as an export lives for the process.
    pub fn start(screen: impl Screen) -> std::io::Result<&'static Self> {
        let latest: &'static Self = Box::leak(Box::new(Self {
            exported: Exported { present },
            next: Mutex::default(),
            arrived: Condvar::new(),
        }));
        std::thread::Builder::new()
            .name("mosh-call-video".into())
            .spawn(move || latest.write(screen))?;
        Ok(latest)
    }

    /// What the app passes back to have a lane shown in this texture.
    pub fn address(&'static self) -> i64 {
        // The export is the first field.
        std::ptr::from_ref(self) as i64
    }

    fn write(&self, mut screen: impl Screen) {
        let mut shown = Frame::default();
        loop {
            {
                let mut next = self
                    .arrived
                    .wait_while(self.next(), |next| !next.fresh)
                    .unwrap_or_else(PoisonError::into_inner);
                next.fresh = false;
                // The two buffers trade places, so a steady stream allocates
                // nothing per frame.
                std::mem::swap(&mut next.frame, &mut shown);
            }
            screen.show(shown.width, shown.height, &shown.pixels);
        }
    }

    fn next(&self) -> MutexGuard<'_, Next> {
        self.next.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

unsafe extern "C" fn present(
    exported: *const Exported,
    pixels: *const u8,
    width: u32,
    height: u32,
) {
    // SAFETY: `exported` is the first field of a leaked `Latest`.
    let latest = unsafe { &*exported.cast::<Latest>() };
    let length = width as usize * height as usize * 4;
    // SAFETY: the caller hands over `width * height * 4` readable bytes.
    let pixels = unsafe { std::slice::from_raw_parts(pixels, length) };
    let mut next = latest.next();
    next.frame.pixels.clear();
    next.frame.pixels.extend_from_slice(pixels);
    (next.frame.width, next.frame.height) = (width, height);
    next.fresh = true;
    latest.arrived.notify_one();
}

#[cfg(target_os = "android")]
mod surface {
    use super::{Latest, Screen};
    use jni::{
        errors::{Error, ThrowRuntimeExAndDefault},
        objects::{JClass, JObject},
        EnvUnowned,
    };
    use ndk::{hardware_buffer_format::HardwareBufferFormat, native_window::NativeWindow};
    use std::{
        io,
        panic::{catch_unwind, AssertUnwindSafe},
    };

    /// One texture's window.
    struct Surface {
        window: NativeWindow,
        refused: bool,
    }

    impl Screen for Surface {
        /// A surface that cannot take a frame keeps what it shows; its
        /// first refusal is logged.
        fn show(&mut self, width: u32, height: u32, rgba: &[u8]) {
            // The window's buffer guard panics if its post fails.
            let posting = AssertUnwindSafe(|| post(&self.window, width, height, rgba));
            let posted = catch_unwind(posting)
                .unwrap_or_else(|_| Err(io::Error::other("the buffer was not posted")));
            let Err(error) = posted else {
                return;
            };
            if !std::mem::replace(&mut self.refused, true) {
                use crate::diagnostics_log::{kinds, write, LogLevel};
                let message = format!("call video texture refused a frame: {error}");
                write(LogLevel::Warn, kinds::CALL, "", &message);
            }
        }
    }

    /// Copies the frame into the window's next buffer and posts it. The
    /// queue's buffers take each frame's size, whatever size the producer
    /// was made with.
    fn post(window: &NativeWindow, width: u32, height: u32, rgba: &[u8]) -> io::Result<()> {
        let format = Some(HardwareBufferFormat::R8G8B8A8_UNORM);
        window.set_buffers_geometry(width as i32, height as i32, format)?;
        let mut buffer = window.lock(None)?;
        if (buffer.width(), buffer.height()) != (width as usize, height as usize) {
            return Err(io::Error::other("a buffer of another size"));
        }
        let lines = buffer
            .lines()
            .ok_or_else(|| io::Error::other("not an RGBA buffer"))?;
        for (line, row) in lines.zip(rgba.chunks_exact(width as usize * 4)) {
            line.write_copy_of_slice(row);
        }
        Ok(())
    }

    /// Called by `MoshCallVideo` with the `Surface` of one texture: the
    /// address the app passes back to have a lane shown in it.
    #[no_mangle]
    pub extern "system" fn Java_app_mosh_mosh_MoshCallVideo_export<'caller>(
        mut unowned: EnvUnowned<'caller>,
        _class: JClass<'caller>,
        surface: JObject<'caller>,
    ) -> i64 {
        unowned
            .with_env(|env| -> Result<i64, Error> {
                // SAFETY: JNI hands over a live environment, and the plugin
                // the `Surface` of a texture it never releases.
                let window = unsafe {
                    NativeWindow::from_surface(env.get_raw().cast(), surface.as_raw().cast())
                }
                .ok_or(Error::NullPtr("call video surface"))?;
                let surface = Surface {
                    window,
                    refused: false,
                };
                // Zero tells the plugin the texture is unavailable.
                Ok(Latest::start(surface).map_or(0, Latest::address))
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::native_call::texture::Texture;
    use std::{sync::mpsc, time::Duration};

    type Shown = (u32, u32, Vec<u8>);

    /// A screen that reports each frame it was given and then stays busy
    /// with it until the test lets it go.
    struct Busy {
        shown: mpsc::Sender<Shown>,
        release: mpsc::Receiver<()>,
    }

    impl Screen for Busy {
        fn show(&mut self, width: u32, height: u32, rgba: &[u8]) {
            let _ = self.shown.send((width, height, rgba.to_vec()));
            let _ = self.release.recv();
        }
    }

    #[test]
    fn a_frame_a_busy_screen_has_not_taken_is_replaced_without_making_its_sender_wait() {
        let (shown, frames) = mpsc::channel();
        let (let_go, release) = mpsc::channel();
        let latest = Latest::start(Busy { shown, release }).unwrap();
        // SAFETY: the address of a leaked export.
        let texture = unsafe { Texture::at(latest.address()) }.unwrap();
        let next = || frames.recv_timeout(Duration::from_secs(5)).unwrap();

        texture.present(1, 1, &[1; 4]);
        assert_eq!(next(), (1, 1, vec![1; 4]));
        // The screen is busy with the first frame: both of these return.
        texture.present(1, 1, &[2; 4]);
        texture.present(2, 1, &[3; 8]);
        let_go.send(()).unwrap();
        assert_eq!(next(), (2, 1, vec![3; 8]));
    }
}
