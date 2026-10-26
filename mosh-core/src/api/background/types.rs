use flutter_rust_bridge::frb;
use serde::Serialize;

#[frb(non_opaque)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BackgroundMode {
    Active,
    Waiting,
    Offline,
    Unsupported,
}

#[frb(non_opaque)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BackgroundReachability {
    Attaching,
    Ready,
    Unavailable,
}

#[frb(non_opaque)]
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct BackgroundStatus {
    pub revision: u64,
    pub interactive: bool,
    pub waiting_enabled: bool,
    pub requested_mode: BackgroundMode,
    pub actual_mode: BackgroundMode,
    pub reachability: BackgroundReachability,
    pub attachment_count: u32,
    pub current_calls: u32,
    pub current_user_transfers: u32,
    pub limitation: Option<String>,
    pub user_transfers: Vec<super::transfers::UserTransfer>,
}
