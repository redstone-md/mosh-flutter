use std::{marker::PhantomData, rc::Rc};

/// Keep the Windows MTA alive until every native audio object has been released.
pub(crate) struct Apartment(PhantomData<Rc<()>>);

impl Apartment {
    pub fn new() -> anyhow::Result<Self> {
        #[cfg(windows)]
        {
            use windows::Win32::System::Com::{COINIT_MULTITHREADED, CoInitializeEx};
            // SAFETY: this !Send guard balances successful initialization on this thread.
            unsafe { CoInitializeEx(None, COINIT_MULTITHREADED).ok()? };
        }
        Ok(Self(PhantomData))
    }
}

impl Drop for Apartment {
    fn drop(&mut self) {
        #[cfg(windows)]
        {
            // SAFETY: the endpoint drops its native objects before this thread-bound guard.
            unsafe { windows::Win32::System::Com::CoUninitialize() };
        }
    }
}
