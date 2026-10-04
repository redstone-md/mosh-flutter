//! Context-free C callbacks deliver into the shared inbox and bounded event ring.
use super::*;
const EVENT_RING_CAPACITY: usize = 64;
static EVENT_LOG: Mutex<Vec<MossEvent>> = Mutex::new(Vec::new());

static MOSS_KEYSTORE: Mutex<Option<Arc<dyn MossKeyStore>>> = Mutex::new(None);

/// Register the persistent backing store for the Moss node identity. Call once
/// (before any node is started) and then `MossFfiRuntime::install_keystore`.
pub fn set_moss_keystore(store: Arc<dyn MossKeyStore>) {
    *MOSS_KEYSTORE.lock().expect("moss keystore lock poisoned") = Some(store);
}

#[cfg(test)]
pub fn clear_moss_keystore() {
    *MOSS_KEYSTORE.lock().expect("moss keystore lock poisoned") = None;
}

#[cfg(test)]
pub(super) fn swap_test_keystore(
    store: Option<Arc<dyn MossKeyStore>>,
) -> Option<Arc<dyn MossKeyStore>> {
    std::mem::replace(
        &mut *MOSS_KEYSTORE.lock().unwrap_or_else(|p| p.into_inner()),
        store,
    )
}

#[cfg(test)]
pub(crate) struct RestoreKeystore(Option<Arc<dyn MossKeyStore>>);

#[cfg(test)]
impl Drop for RestoreKeystore {
    fn drop(&mut self) {
        let _ = swap_test_keystore(self.0.take());
    }
}

#[cfg(test)]
pub(crate) fn replace_test_keystore(store: Option<Arc<dyn MossKeyStore>>) -> RestoreKeystore {
    RestoreKeystore(swap_test_keystore(store))
}

pub(super) unsafe extern "C" fn on_moss_message(
    channel: *const c_char,
    _sender_id: *const u8,
    data: *const u8,
    len: u32,
) {
    if channel.is_null() || data.is_null() {
        return;
    }

    let channel = unsafe { std::ffi::CStr::from_ptr(channel) }
        .to_string_lossy()
        .into_owned();
    let payload = unsafe { std::slice::from_raw_parts(data, len as usize) }.to_vec();

    crate::inbox::deliver(MossReceivedMessage { channel, payload });
}

pub(super) unsafe extern "C" fn keystore_load(buffer: *mut u8, capacity: u32) -> u32 {
    let guard = MOSS_KEYSTORE.lock().expect("moss keystore lock poisoned");
    let Some(store) = guard.as_ref() else {
        return 0;
    };
    let Some(bytes) = store.load_identity() else {
        return 0;
    };
    let len = bytes.len() as u32;
    if buffer.is_null() || capacity == 0 {
        return len; // size probe
    }
    if capacity < len {
        return 0; // buffer too small; Moss probes first, so this is defensive
    }
    unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len()) };
    identity::capture_identity(&bytes);
    len
}

/// Moss identity save callback. Persists the encoded identity bytes through the
/// registered host store.
pub(super) unsafe extern "C" fn keystore_save(data: *const u8, len: u32) {
    if data.is_null() || len == 0 {
        return;
    }
    let bytes = unsafe { std::slice::from_raw_parts(data, len as usize) }.to_vec();
    identity::capture_identity(&bytes);
    let guard = MOSS_KEYSTORE.lock().expect("moss keystore lock poisoned");
    if let Some(store) = guard.as_ref() {
        store.save_identity(&bytes);
    }
}

pub(super) unsafe extern "C" fn on_moss_event(event_type: i32, detail_json: *const c_char) {
    let detail = if detail_json.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(detail_json) }
            .to_string_lossy()
            .into_owned()
    };
    push_app_event(event_type, &detail);
}

pub fn push_app_event(event_type: i32, detail_json: &str) {
    let epoch_millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0);

    let mut log = EVENT_LOG.lock().expect("Moss event lock poisoned");
    log.push(MossEvent {
        event_type,
        detail_json: detail_json.to_string(),
        epoch_millis,
    });
    if log.len() > EVENT_RING_CAPACITY {
        let drop = log.len() - EVENT_RING_CAPACITY;
        log.drain(0..drop);
    }
}

pub(super) unsafe extern "C" fn on_stream_payload(
    peer_id: *const c_char,
    data: *const u8,
    len: u32,
) {
    if peer_id.is_null() || data.is_null() {
        return;
    }
    let peer_id = unsafe { CStr::from_ptr(peer_id) }
        .to_string_lossy()
        .into_owned();
    let payload = unsafe { std::slice::from_raw_parts(data, len as usize) }.to_vec();
    let channel = if crate::device_link::wire::is_device_link_packet(&payload) {
        crate::device_link::transport::LINK_CHANNEL.to_string()
    } else {
        crate::stream_transport::stream_inbox_channel(&peer_id)
    };
    crate::inbox::deliver(MossReceivedMessage { channel, payload });
}

pub fn drain_received_messages() -> Vec<MossReceivedMessage> {
    crate::inbox::drain_all()
}

pub fn snapshot_event_log() -> Vec<MossEvent> {
    EVENT_LOG
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone()
}

pub fn clear_event_log() {
    EVENT_LOG
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clear();
}

pub fn wait_for_payload(payload: &[u8]) -> Result<MossReceivedMessage, MossFfiError> {
    let deadline = std::time::Instant::now() + Duration::from_millis(DEFAULT_WAIT_MS);

    while std::time::Instant::now() < deadline {
        if let Some(message) = drain_received_messages()
            .into_iter()
            .find(|message| message.payload == payload)
        {
            return Ok(message);
        }

        std::thread::sleep(Duration::from_millis(POLL_MS));
    }

    Err(MossFfiError::DeliveryTimeout)
}
