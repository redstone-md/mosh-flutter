//! Independent linked MLS clients in one DM, ADR 0030.
mod admission;
#[cfg(test)]
mod authorization_tests;
mod live;
mod proof;
mod receipts;
mod runtime;
mod types;

pub(super) use live::DeviceSignature;
pub(super) use runtime::DeviceDmLink;
pub(crate) use types::DeviceMembership;
pub(super) const DEVICE_CHANNEL: &str = "mosh-dm-devices-v1";
const RETRY_MS: u64 = 2_000;
const INVALID: &str = "invalid DM device authorization";
const NO_DEVICE_PEERS: &str = "no admitted DM device is reachable";
const MAX_PACKET_BYTES: usize = 128 * 1024;
const DM_USERS: usize = 2;
const INITIAL_CLIENTS: usize = DM_USERS;

pub(super) fn invalid() -> super::PrivateDmRuntimeError {
    super::PrivateDmRuntimeError::Codec(INVALID.into())
}
