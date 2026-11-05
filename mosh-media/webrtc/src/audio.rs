//! Audio devices through libwebrtc's platform audio module, and Opus as
//! Mosh sends it.
use anyhow::Result;
use libwebrtc::peer_connection::PeerConnection;
use libwebrtc::peer_connection_factory::{PeerConnectionFactory, native::PeerConnectionFactoryExt};
use serde_json::{Value, json};

pub fn devices(factory: &PeerConnectionFactory) -> Value {
    let inputs: Vec<_> = (0..factory.recording_devices().max(0) as u16)
        .map(|i| json!({"id": factory.recording_device_guid(i), "name": factory.recording_device_name(i)}))
        .collect();
    let outputs: Vec<_> = (0..factory.playout_devices().max(0) as u16)
        .map(|i| json!({"id": factory.playout_device_guid(i), "name": factory.playout_device_name(i)}))
        .collect();
    json!({"inputs": inputs, "outputs": outputs})
}

/// Selects devices by id; a missing id means the system default.
pub fn select(factory: &PeerConnectionFactory, value: &Value) -> Value {
    let input_ok = match value["input"].as_str() {
        Some(id) => factory.set_recording_device_by_guid(id),
        None => factory.set_recording_device(0),
    };
    let output_ok = match value["output"].as_str() {
        Some(id) => factory.set_playout_device_by_guid(id),
        None => factory.set_playout_device(0),
    };
    json!({"input_ok": input_ok, "output_ok": output_ok})
}

/// Ranks RED (RFC 2198) ahead of plain Opus, as Chrome's RED trial does:
/// each 20 ms packet repeats the previous frame, so a single lost packet is
/// recovered whole. On the bench (30 ms, 224 kbit/s) it concealed 0.4% of
/// audio at 5% loss and 1.3% at 15%, against 5% and 16% with RingRTC, for
/// about 21 kbit/s. DTX was left off: it cost RED most of that gain. Longer
/// packets halve the 50 packets/s but add delay and concealment.
pub fn prefer_red(factory: &PeerConnectionFactory, pc: &PeerConnection) -> Result<()> {
    let mut codecs = factory
        .get_rtp_sender_capabilities(libwebrtc::MediaType::Audio)
        .codecs;
    codecs.sort_by_key(|codec| !codec.mime_type.eq_ignore_ascii_case("audio/red"));
    for transceiver in pc.transceivers() {
        transceiver
            .set_codec_preferences(codecs.clone())
            .map_err(|error| anyhow::anyhow!("codec preferences: {error:?}"))?;
    }
    Ok(())
}
