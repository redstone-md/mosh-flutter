//! Moss carrier framing and the audio payload types used for priority.
use std::sync::Mutex;

/// `MV1`, source port and destination port, then the UDP payload.
pub fn encode(source: u16, destination: u16, data: &[u8]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(7 + data.len());
    bytes.extend(b"MV1");
    bytes.extend(source.to_be_bytes());
    bytes.extend(destination.to_be_bytes());
    bytes.extend(data);
    bytes
}

pub fn learn_audio_payloads(sdp: &str, audio: &Mutex<[bool; 128]>) {
    if let Ok(mut audio) = audio.lock() {
        for line in sdp.lines().filter(|line| line.starts_with("m=audio ")) {
            for payload in line.split_ascii_whitespace().skip(3) {
                if let Ok(payload) = payload.parse::<usize>()
                    && payload < audio.len()
                {
                    audio[payload] = true;
                }
            }
        }
    }
}
