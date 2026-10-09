//! Moss C ABI and checked symbol/return-value conversion.
use super::*;

pub(super) type MessageCallback = unsafe extern "C" fn(*const c_char, *const u8, *const u8, u32);
pub(super) type EventCallback = unsafe extern "C" fn(i32, *const c_char);
pub(super) type MossInit =
    unsafe extern "C" fn(*const c_char, *const u8, *const c_char) -> MossHandle;
pub(super) type MossStart = unsafe extern "C" fn(MossHandle) -> i32;
pub(super) type MossStop = unsafe extern "C" fn(MossHandle) -> i32;
pub(super) type MossSubscribe = unsafe extern "C" fn(MossHandle, *const c_char) -> i32;
pub(super) type MossJoinRoom =
    unsafe extern "C" fn(MossHandle, *const c_char, *const u8, u32) -> i32;
pub(super) type MossRoomChannel =
    unsafe extern "C" fn(MossHandle, *const c_char, *const c_char) -> i32;
pub(super) type MossPublishRoom =
    unsafe extern "C" fn(MossHandle, *const c_char, *const c_char, *const u8, u32) -> i32;
pub(super) type MossConnect = unsafe extern "C" fn(MossHandle, *const c_char) -> i32;
pub(super) type MossPublish =
    unsafe extern "C" fn(MossHandle, *const c_char, *const u8, u32) -> i32;
pub(super) type MossSetCallback = unsafe extern "C" fn(MossHandle, Option<MessageCallback>) -> i32;
pub(super) type MossSetEventCallback =
    unsafe extern "C" fn(MossHandle, Option<EventCallback>) -> i32;
pub(super) type MossGetMeshInfo = unsafe extern "C" fn(MossHandle) -> *mut c_char;
pub(super) type MossGetNatType = unsafe extern "C" fn(MossHandle) -> *mut c_char;
pub(super) type MossGetPublicKey = unsafe extern "C" fn(MossHandle) -> *mut u8;
pub(super) type MossFree = unsafe extern "C" fn(*mut c_void);
pub(super) type KeyStoreLoadCallback = unsafe extern "C" fn(*mut u8, u32) -> u32;
pub(super) type KeyStoreSaveCallback = unsafe extern "C" fn(*const u8, u32);
pub(super) type MossSetKeyStore =
    unsafe extern "C" fn(Option<KeyStoreLoadCallback>, Option<KeyStoreSaveCallback>) -> i32;

pub(super) type MossVersionFn = unsafe extern "C" fn() -> *mut c_char;
pub(super) type MossLastErrorFn = unsafe extern "C" fn(MossHandle) -> *mut c_char;
pub(super) type MossPeerRttFn = unsafe extern "C" fn(MossHandle, *const c_char) -> i64;
pub(super) type MossOpenStreamFn = unsafe extern "C" fn(MossHandle, *const c_char, u32) -> i32;
pub(super) type MossSendStreamFn =
    unsafe extern "C" fn(MossHandle, *const c_char, u32, *const u8, u32) -> i32;
// Callback shape mirrors moss's MossStreamCallback C typedef: a heap-allocated
// peer-id string (hex) and the payload bytes; the caller frees both copies.
pub(super) type StreamCallback = unsafe extern "C" fn(*const c_char, *const u8, u32);
pub(super) type MossOnStreamFn =
    unsafe extern "C" fn(MossHandle, u32, Option<StreamCallback>) -> i32;
pub(super) type MossSendToPeerFn =
    unsafe extern "C" fn(MossHandle, *const c_char, *const u8, i32) -> i32;
pub(super) type PacketCallback = unsafe extern "C" fn(*const u8, *const u8, u32);
pub(super) type MossSetPacketCallbackFn =
    unsafe extern "C" fn(MossHandle, Option<PacketCallback>) -> i32;

pub(super) fn load_symbol<T: Copy>(library: &Library, name: &[u8]) -> Result<T, MossFfiError> {
    let symbol: Symbol<T> =
        unsafe { library.get(name) }.map_err(|_| MossFfiError::Symbol(symbol_name(name)))?;

    Ok(*symbol)
}

pub(super) fn try_load_symbol<T: Copy>(library: &Library, name: &[u8]) -> Option<T> {
    unsafe { library.get::<T>(name) }.ok().map(|symbol| *symbol)
}

pub(super) fn c_string(value: &str) -> Result<CString, MossFfiError> {
    CString::new(value).map_err(|_| MossFfiError::InvalidCString(value.to_string()))
}

pub(super) fn check_code(name: &'static str, code: i32) -> Result<(), MossFfiError> {
    if code == MOSS_OK {
        Ok(())
    } else {
        Err(MossFfiError::Operation { name, code })
    }
}

pub(super) fn check_publish_code(code: i32) -> Result<(), MossFfiError> {
    match code {
        c if c == MOSS_OK => Ok(()),
        c if c == MOSS_ERR_NO_PEERS => Err(MossFfiError::NoPeers),
        other => Err(MossFfiError::Operation {
            name: "publish",
            code: other,
        }),
    }
}

fn symbol_name(name: &[u8]) -> String {
    let name = name.strip_suffix(&[0]).unwrap_or(name);

    String::from_utf8_lossy(name).into_owned()
}

pub(super) fn take_heap_string(ptr: *mut c_char, free: &MossFree) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let value = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { free(ptr as *mut c_void) };
    Some(value)
}
