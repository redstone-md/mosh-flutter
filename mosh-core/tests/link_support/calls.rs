use aes_gcm::{aead::Aead, Aes256Gcm, KeyInit, Nonce};
use base64::{engine::general_purpose::STANDARD, Engine};
use mosh_core::api::{private_dm, voice_call_opus_encode as opus, voice_call_playback as playback};
use serde_json::{json, Value};

pub(super) struct CallProbe {
    call_id: String,
    seq: u64,
    received: usize,
    encoder: opus::VoiceCallOpusEncoder,
    playback: playback::VoicePlayback,
}

pub(super) fn command(
    action: &str,
    session: &str,
    args: &Value,
    probe: &mut Option<CallProbe>,
) -> Value {
    let call = args["call_id"].as_str().unwrap_or_default().to_owned();
    let matches_probe = probe.as_ref().is_some_and(|probe| probe.call_id == call);
    let result = match action {
        "call_start" => {
            return match private_dm::call_start(session.into()) {
                Ok(started) => serde_json::to_value(started).unwrap(),
                Err(error) => json!({"error": format!("{:?}", error.kind)}),
            }
        }
        "call_accept" => private_dm::call_accept(session.into(), call),
        "call_decline" => private_dm::call_decline(session.into(), call, "declined".into()),
        "call_end" => private_dm::call_end(session.into(), call, "hangup".into()),
        "call_probe" => return media(session, probe),
        _ => panic!("unknown call command"),
    };
    if result.is_ok() && matches_probe && matches!(action, "call_end" | "call_decline") {
        *probe = None;
    }
    match result {
        Ok(()) => json!({}),
        Err(error) => json!({"error": format!("{:?}", error.kind)}),
    }
}

fn media(session: &str, slot: &mut Option<CallProbe>) -> Value {
    let active = private_dm::poll_session(session.into())
        .unwrap()
        .active_call
        .unwrap();
    if slot
        .as_ref()
        .is_none_or(|probe| probe.call_id != active.call_id)
    {
        *slot = Some(CallProbe {
            call_id: active.call_id.clone(),
            seq: 0,
            received: 0,
            encoder: opus::voice_call_opus_encoder_new().unwrap(),
            playback: playback::voice_call_playback_start(None).unwrap(),
        });
    }
    let probe = slot.as_mut().unwrap();
    let key = STANDARD.decode(active.key_b64).unwrap();
    let prefix = STANDARD.decode(active.nonce_prefix_b64).unwrap();
    let cipher = Aes256Gcm::new_from_slice(&key).unwrap();
    let frames = private_dm::call_drain_frames(session.into(), active.call_id.clone()).unwrap();
    for wire in frames {
        let seq = u64::from_be_bytes(wire[..8].try_into().unwrap());
        let mut nonce = [0_u8; 12];
        nonce[..4].copy_from_slice(&prefix);
        nonce[4..].copy_from_slice(&wire[..8]);
        let packet = cipher
            .decrypt(Nonce::from_slice(&nonce), &wire[8..])
            .unwrap();
        playback::voice_call_playback_push_frame(&probe.playback, seq as u128, packet).unwrap();
        probe.received += 1;
    }
    send_tone(
        session,
        &active.call_id,
        &active.direction,
        &prefix,
        &cipher,
        probe,
    );
    json!({"received": probe.received, "sent": probe.seq})
}

fn send_tone(
    session: &str,
    call_id: &str,
    direction: &str,
    prefix: &[u8],
    cipher: &Aes256Gcm,
    probe: &mut CallProbe,
) {
    for _ in 0..10 {
        let seq = probe.seq | if direction == "callee" { 1 << 63 } else { 0 };
        let pcm: Vec<u8> = (0..960)
            .flat_map(|i| {
                let t = (probe.seq * 960 + i) as f64 / 48_000.0;
                let sample = ((t * std::f64::consts::TAU * 440.0).sin() * 2000.0).round() as i16;
                sample.to_le_bytes()
            })
            .collect();
        let packet = opus::voice_call_opus_encode(&probe.encoder, pcm).unwrap();
        let mut nonce = [0_u8; 12];
        nonce[..4].copy_from_slice(prefix);
        nonce[4..].copy_from_slice(&seq.to_be_bytes());
        let encrypted = cipher
            .encrypt(Nonce::from_slice(&nonce), packet.as_slice())
            .unwrap();
        let mut wire = seq.to_be_bytes().to_vec();
        wire.extend(encrypted);
        private_dm::call_send_frame(session.into(), call_id.into(), wire).unwrap();
        probe.seq += 1;
    }
}
