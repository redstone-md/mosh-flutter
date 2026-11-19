//! What a device accepts as a member's wake address.

use super::*;

pub(crate) const SERVICE: &str = "https://wake.example";
pub(crate) const HANDLE: &str = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJ0123456";

pub(crate) fn announcement(handle: &str, service: &str, issued_at_ms: u64) -> WakeAnnouncement {
    WakeAnnouncement {
        wake_address: WakeAddress {
            service: service.to_string(),
            handle: handle.to_string(),
        },
        issued_at_ms,
        preview_key: None,
    }
}

fn devices() -> Devices {
    Devices::new(BTreeMap::new(), 0)
}

// A replayed older frame must not bring back a handle the device replaced
// or withdrew; a repeat is kept but changes nothing.
#[test]
fn only_a_newer_announcement_replaces_the_held_one() {
    let mut devices = devices();
    assert_eq!(
        devices.accept("signer".into(), announcement(HANDLE, SERVICE, 2)),
        Some(true)
    );
    assert_eq!(
        devices.accept("signer".into(), announcement("", SERVICE, 1)),
        None
    );
    assert_eq!(
        devices.accept("signer".into(), announcement("", SERVICE, 2)),
        None
    );
    assert_eq!(
        devices.accept("signer".into(), announcement(HANDLE, SERVICE, 3)),
        Some(false)
    );
    assert_eq!(
        devices.accept("signer".into(), announcement("", SERVICE, 4)),
        Some(true)
    );
}

// The address turns into an HTTP request on the receiving device.
#[test]
fn an_address_off_the_service_shape_is_refused() {
    let mut devices = devices();
    let long = format!("https://{}", "w".repeat(SERVICE_MAX_LEN));
    for (handle, service) in [
        (HANDLE, "http://wake.example"),
        ("short", SERVICE),
        (HANDLE, long.as_str()),
        (HANDLE, "https://wake.example/a b"),
    ] {
        assert_eq!(
            devices.accept("a".into(), announcement(handle, service, 1)),
            None
        );
    }
}

// A key replaced in the same millisecond as the last announcement must
// still reach members.
#[test]
fn a_change_in_the_same_millisecond_is_still_newer() {
    let address = WakeAddress {
        service: SERVICE.to_string(),
        handle: HANDLE.to_string(),
    };
    let mut own = OwnWake::default();
    let mut devices = devices();
    let first = own.next(&address, 5).body;
    own.sent(first.clone(), None);
    devices.accept("phone".into(), first);

    own.keys.replace(5);
    let second = own.next(&address, 5).body;

    assert_eq!(own.due(&second, None, u64::MAX), Some(true));
    assert_eq!(devices.accept("phone".into(), second), Some(true));
}
