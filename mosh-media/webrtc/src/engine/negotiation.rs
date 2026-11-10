//! What crosses mosh-core's signaling: the SDP each side makes and the ICE
//! candidates it gathers, read and checked on the way in.
use std::sync::mpsc::{Receiver, sync_channel};

use anyhow::{Context, Result};
use libwebrtc::{
    ice_candidate::IceCandidate,
    peer_connection::{OfferOptions, PeerConnection},
    session_description::{SdpType, SessionDescription},
};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::Description;

#[derive(Serialize, Deserialize)]
struct Candidate {
    mid: String,
    index: i32,
    sdp: String,
}

/// The peer's SDP, which must carry the DTLS fingerprint the handshake checks.
pub(super) fn parse_description(remote: &Description) -> Result<SessionDescription> {
    anyhow::ensure!(remote.parameters.len() <= 16_384, "description too large");
    let sdp = std::str::from_utf8(&remote.parameters)?;
    anyhow::ensure!(
        sdp.contains("a=fingerprint:"),
        "description lacks a DTLS fingerprint"
    );
    let kind = if remote.offer {
        SdpType::Offer
    } else {
        SdpType::Answer
    };
    SessionDescription::parse(sdp, kind).map_err(|error| anyhow::anyhow!("sdp: {error:?}"))
}

/// The caller's offer, with fresh ICE credentials for a restart.
pub(super) fn offer_options(ice_restart: bool) -> OfferOptions {
    // The bindings' default sets the legacy offerToReceiveAudio to false,
    // which makes the offer send-only and leaves the callee unheard.
    OfferOptions {
        ice_restart,
        offer_to_receive_audio: None,
        offer_to_receive_video: None,
    }
}

/// Whether `remote` moves the negotiation on from `accepted`, when this side
/// `expects` a new description at all (the caller only for its pending
/// restart). Signals arrive twice or late: the peer's session version, which
/// grows with each description it makes, tells an old one from the next.
pub(super) fn advances(
    remote: &Description,
    accepted: Option<&Description>,
    expects: bool,
) -> Result<bool> {
    let Some(accepted) = accepted else {
        return Ok(true);
    };
    Ok(expects && session_version(remote)? > session_version(accepted)?)
}

/// The session version in the SDP origin line, `o=- <id> <version> ...`.
fn session_version(description: &Description) -> Result<u64> {
    let sdp = std::str::from_utf8(&description.parameters)?;
    sdp.lines()
        .find_map(|line| line.strip_prefix("o="))
        .and_then(|origin| origin.split_whitespace().nth(2))
        .and_then(|version| version.parse().ok())
        .context("description lacks a session version")
}

/// A candidate the peer gathered, as `gather_candidates` encodes it.
pub(super) fn parse_candidate(value: &Value) -> Result<IceCandidate> {
    let text = value.as_str().filter(|text| text.len() <= 2048);
    let candidate: Candidate = serde_json::from_str(text.context("candidate")?)?;
    IceCandidate::parse(&candidate.mid, candidate.index, &candidate.sdp)
        .map_err(|error| anyhow::anyhow!("candidate: {error:?}"))
}

/// Queues each gathered ICE candidate as JSON for the next tick.
pub(super) fn gather_candidates(pc: &PeerConnection) -> Receiver<String> {
    let (sender, candidates) = sync_channel(32);
    pc.on_ice_candidate(Some(Box::new(move |candidate: IceCandidate| {
        let encoded = serde_json::to_string(&Candidate {
            mid: candidate.sdp_mid(),
            index: candidate.sdp_mline_index(),
            sdp: candidate.candidate(),
        });
        if let Ok(encoded) = encoded {
            let _ = sender.try_send(encoded);
        }
    })));
    candidates
}
