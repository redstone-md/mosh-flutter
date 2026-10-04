//! Runtime measurements and identity copied from Moss-owned buffers.
use super::*;

impl MossNode {
    pub fn last_error(&self) -> Option<String> {
        let last_error = self.runtime.last_error?;
        take_heap_string(unsafe { last_error(self.handle) }, &self.runtime.free)
            .filter(|reason| !reason.is_empty())
    }

    pub fn public_key_hex(&self) -> Option<String> {
        #[cfg(test)]
        if take_test_public_key_unavailable() {
            return None;
        }
        let ptr = unsafe { (self.runtime.get_public_key)(self.handle) };
        if ptr.is_null() {
            return None;
        }
        // SAFETY: Moss_GetPublicKey on the Go side always returns a buffer
        // sized by the MOSS_PUBKEY_LEN-byte Ed25519 public key. Reading any
        // other length would be UB; the constant locks the contract.
        let bytes = unsafe { std::slice::from_raw_parts(ptr, MOSS_PUBKEY_LEN) }.to_vec();
        unsafe { (self.runtime.free)(ptr as *mut c_void) };
        Some(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
    }

    pub fn library_version(&self) -> Option<String> {
        let version = unsafe { (self.runtime.version?)() };
        take_heap_string(version, &self.runtime.free)
    }

    pub fn peer_rtt_ns(&self, peer_id: &str) -> Option<u64> {
        let rtt =
            unsafe { (self.runtime.peer_rtt?)(self.handle, c_string(peer_id).ok()?.as_ptr()) };
        u64::try_from(rtt).ok().filter(|nanos| *nanos > 0)
    }

    pub fn mesh_info_json(&self) -> Option<String> {
        take_heap_string(
            unsafe { (self.runtime.get_mesh_info)(self.handle) },
            &self.runtime.free,
        )
    }

    pub fn nat_type(&self) -> Option<String> {
        take_heap_string(
            unsafe { (self.runtime.get_nat_type)(self.handle) },
            &self.runtime.free,
        )
    }
}

/// Cache the library version without constructing a throwaway node.
pub fn library_version_once() -> Option<String> {
    static VERSION: LazyLock<Option<String>> = LazyLock::new(|| {
        let runtime = MossFfiRuntime::load_default().ok()?;
        let version = unsafe { (runtime.version?)() };
        take_heap_string(version, &runtime.free)
    });
    VERSION.clone()
}
