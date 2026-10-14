//! Scope macOS timer scheduling to owned media threads; idle callers keep their QoS.
use std::{marker::PhantomData, rc::Rc};

pub(super) struct Priority {
    #[cfg(target_os = "macos")]
    previous: Option<(u32, i32)>,
    // A thread's scheduling class must be restored on that same thread.
    _thread: PhantomData<Rc<()>>,
}

impl Priority {
    pub fn new() -> Self {
        #[cfg(target_os = "macos")]
        let previous = current().and_then(|previous| {
            (previous.0 != INTERACTIVE)
                .then(|| set_class(INTERACTIVE, 0).map(|()| previous))
                .flatten()
        });
        Self {
            #[cfg(target_os = "macos")]
            previous,
            _thread: PhantomData,
        }
    }
}

impl Drop for Priority {
    fn drop(&mut self) {
        #[cfg(target_os = "macos")]
        if let Some((class, relative)) = self.previous {
            let _ = set_class(class, relative);
        }
    }
}

#[cfg(target_os = "macos")]
const INTERACTIVE: u32 = 0x21;
#[cfg(target_os = "macos")]
const DEFAULT: u32 = 0x15;

#[cfg(target_os = "macos")]
fn current() -> Option<(u32, i32)> {
    let mut class = 0;
    let mut relative = 0;
    // SAFETY: pthread_self is live; distinct initialized outputs stay writable
    // through the synchronous call. Darwin's qos_class_t is an unsigned int.
    let status = unsafe { pthread_get_qos_class_np(pthread_self(), &mut class, &mut relative) };
    // Darwin cannot set UNSPECIFIED; an unclassified thread returns to DEFAULT.
    checked(status).map(|()| (if class == 0 { DEFAULT } else { class }, relative))
}

#[cfg(target_os = "macos")]
fn set_class(class: u32, relative: i32) -> Option<()> {
    // SAFETY: values are either documented interactive/zero or returned by
    // Darwin for this thread. No pointers or ownership cross this ABI.
    let status = unsafe { pthread_set_qos_class_self_np(class, relative) };
    checked(status)
}

#[cfg(target_os = "macos")]
fn checked(status: i32) -> Option<()> {
    if status == 0 {
        Some(())
    } else {
        use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
        dlog::write(
            LogLevel::Warn,
            kinds::CALL,
            "media-thread",
            &format!(
                "could not configure thread QoS: {}",
                std::io::Error::from_raw_os_error(status)
            ),
        );
        None
    }
}

#[cfg(target_os = "macos")]
extern "C" {
    fn pthread_self() -> *mut std::ffi::c_void;
    fn pthread_get_qos_class_np(
        thread: *mut std::ffi::c_void,
        class: *mut u32,
        relative_priority: *mut std::ffi::c_int,
    ) -> std::ffi::c_int;
    fn pthread_set_qos_class_self_np(
        class: u32,
        relative_priority: std::ffi::c_int,
    ) -> std::ffi::c_int;
}

#[cfg(all(test, target_os = "macos"))]
mod tests {
    use super::*;

    #[test]
    fn media_priority_is_applied_and_restored_on_its_own_thread() {
        let previous = current().unwrap();
        {
            let priority = Priority::new();
            assert!(
                previous.0 == INTERACTIVE || priority.previous.is_some(),
                "macOS rejected media QoS"
            );
            assert_eq!(current().unwrap().0, INTERACTIVE);
        }
        assert_eq!(current().unwrap(), previous);
    }
}
