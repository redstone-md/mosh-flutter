//! Headless DM, group and channel reachability probes. Output is NDJSON.

use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use clap::Parser;
use mosh_core::attachment_store::AttachmentStore;
use mosh_core::channel_runtime::{
    ChannelRuntime, ChannelSendResult, ChannelSnapshot, JoinChannelRequest,
};
use mosh_core::conversation::mesh::{MeshInfo, SnapshotEvent};
use mosh_core::moss_ffi::MossFfiRuntime;
use mosh_core::moss_runtime::MossDynamicRuntime;
use mosh_core::network_inventory;
use mosh_core::outbound_delivery::MessageDeliveryStatus;
use mosh_core::private_dm_runtime::{
    AcceptInviteRequest, DmSessionState, PrivateDmRuntime, SessionSnapshot, StartSessionRequest,
};
use mosh_core::private_group_runtime::{
    CreateGroupRequest, GroupSnapshot, JoinGroupRequest, PrivateGroupRuntime,
};

const TICK: Duration = Duration::from_millis(500);

const NO_PEERS_TEXT: &str = "no peers yet, so the message did not go out";

mod telemetry;
use telemetry::*;
mod runtime;
use runtime::*;
mod doctor;
use doctor::*;
mod dm;
use dm::*;
mod dm_many;
use dm_many::*;
mod group;
use group::*;
mod channel;
use channel::*;
mod cli;
use cli::{Cli, Command};
mod dispatch;

fn main() {
    dispatch::run();
}

#[cfg(test)]
mod tests;
