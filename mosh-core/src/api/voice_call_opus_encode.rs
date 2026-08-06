//! Opus encoder facade for the voice-call capture pipeline.
//!
//! Mirrors the React `mosh/src/features/private-dm/voice-call/audio-capture.ts`
//! WebCodecs Opus encoder: 48 kHz mono, 24 kbps, 20 ms frames (960 samples).
//! The `record` Dart package captures PCM16 natively (its Opus encoder is
//! Android/iOS/Linux only), so the Opus encode happens here in Rust via the
//! high-level `audiopus` crate (vendored libopus, built with MSVC -- no vcpkg).
//!
//! frb contract: the encoder is opaque across the FFI seam (it holds a raw
//! libopus pointer that is `Send` but not `Sync`); each Dart call borrows the
//! single owned encoder mutably, encodes one 1920-byte (960 i16 LE) frame, and
//! returns the Opus packet bytes. DTX comfort-noise packets (1-3 bytes) are
//! returned as-is -- the Dart side decides whether to emit them.

use std::sync::Mutex;

use audiopus::{coder::Encoder, Application, Bitrate, Channels, SampleRate};
use flutter_rust_bridge::frb;

/// One Opus packet's max byte length (RFC 6716: 20 ms frames at 24 kbps cap
/// well under 4000 bytes; 4000 is libopus's documented per-packet ceiling).
const OPUS_MAX_PACKET_BYTES: usize = 4000;

/// Opaque wrapper over `audiopus::Encoder`. The raw encoder owns a libopus
/// `OpusEncoder*` (not frb-serializable, and `Send` but not `Sync`), so it is
/// marked `#[frb(opaque)]` -- the Dart side holds it as an opaque handle and
/// borrows it mutably per `voice_call_opus_encode` call. The encoder is wrapped
/// in a `Mutex` so the wrapper is `Send + Sync` (frb's default `RustAutoOpaqueMoi`
/// pool stores the opaque behind a `RwLock` + `Arc` pool that requires `Sync`).
#[frb(opaque)]
pub struct VoiceCallOpusEncoder {
    encoder: Mutex<Encoder>,
}

/// Constructs a 48 kHz mono VoIP Opus encoder at 24 kbps, mirroring the React
/// WebCodecs encoder config. Synchronous (no I/O); `Err(String)` on libopus
/// init or bitrate-set failure. Errors are stringified via `Debug` to keep the
/// bridge surface a plain `Result<T, String>` (matches `voice_call_*` style).
#[frb(sync)]
pub fn voice_call_opus_encoder_new() -> Result<VoiceCallOpusEncoder, String> {
    let mut encoder = Encoder::new(SampleRate::Hz48000, Channels::Mono, Application::Voip)
        .map_err(|e| format!("opus encoder init: {e:?}"))?;
    encoder
        .set_bitrate(Bitrate::BitsPerSecond(24000))
        .map_err(|e| format!("opus set_bitrate: {e:?}"))?;
    Ok(VoiceCallOpusEncoder {
        encoder: Mutex::new(encoder),
    })
}

/// Encodes one 20 ms PCM16 frame to an Opus packet. `pcm16` is 1920 bytes (960
/// little-endian i16 samples, host-native from `record`'s `pcm16bits` stream);
/// any other length is rejected so a framing slip surfaces as a hard error
/// rather than a silently mis-encoded frame. Returns the Opus packet bytes
/// (1-3 bytes for a DTX comfort-noise frame, longer for real speech). The
/// encoder is locked for the duration of the encode (single-threaded use).
#[frb(sync)]
pub fn voice_call_opus_encode(
    encoder: &VoiceCallOpusEncoder,
    pcm16: Vec<u8>,
) -> Result<Vec<u8>, String> {
    if pcm16.len() != 1920 {
        return Err(format!(
            "opus encode: expected 1920 bytes (960 i16), got {}",
            pcm16.len()
        ));
    }
    let samples: Vec<i16> = pcm16
        .chunks_exact(2)
        .map(|pair| i16::from_le_bytes([pair[0], pair[1]]))
        .collect();
    let mut out = vec![0u8; OPUS_MAX_PACKET_BYTES];
    let guard = encoder
        .encoder
        .lock()
        .map_err(|e| format!("opus encode: mutex poisoned: {e}"))?;
    let written = guard
        .encode(&samples, &mut out)
        .map_err(|e| format!("opus encode: {e:?}"))?;
    out.truncate(written);
    Ok(out)
}
