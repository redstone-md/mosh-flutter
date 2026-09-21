//! AES-GCM frame seal/open for a 1:1 voice call, per ADR 0012. This crate
//! owns the wire format; both call participants must produce/consume the
//! same wire bytes.
//!
//! Wire frame layout: `[seq:u64 BE][ciphertext-with-tag]`. AES-GCM nonce =
//! `[nonce_prefix (4)][seq (8 BE)]`. The high bit of `seq` distinguishes
//! direction so the two participants never collide nonces while sharing one
//! key: CALLER = 0, CALLEE = `1 << 63`. The low 63 bits carry the seq value;
//! `seal_frame` rejects a seq value that would overflow that space (no
//! silent mask-wrap into a reused nonce).

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Key, Nonce};

/// Direction bit for the caller half of the seq space.
pub const CALLER_DIRECTION_BIT: u64 = 0;
/// Direction bit for the callee half of the seq space (`1 << 63`).
pub const CALLEE_DIRECTION_BIT: u64 = 1u64 << 63;
/// Mask selecting the low 63 bits of `seq` (the actual seq value).
pub const SEQ_VALUE_MASK: u64 = (1u64 << 63) - 1;
/// Length of the seq header on the wire (u64 big-endian).
pub const SEQ_LEN: usize = 8;
/// Length of the AES-GCM nonce (4-byte prefix + 8-byte seq).
pub const NONCE_LEN: usize = 12;
/// Length of the AES-256 key (bytes).
pub const KEY_LEN: usize = 32;
/// Length of the nonce prefix (bytes).
pub const NONCE_PREFIX_LEN: usize = 4;
/// Minimum frame length: seq header + at least one byte of ciphertext+tag.
pub const MIN_FRAME_LEN: usize = SEQ_LEN + 1;

/// Errors from `open_frame`: malformed wire frame or AEAD auth failure.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrameCryptoError {
    /// Frame shorter than the seq header + a non-empty ciphertext+tag.
    MalformedFrame,
    /// AES-GCM tag verification failed (tamper / wrong key / wrong nonce).
    AuthFailed,
}

/// Build the 12-byte AES-GCM nonce: `[nonce_prefix (4)][seq (8 BE)]`.
fn build_nonce(nonce_prefix: &[u8; NONCE_PREFIX_LEN], seq: u64) -> [u8; NONCE_LEN] {
    let mut nonce = [0u8; NONCE_LEN];
    nonce[..NONCE_PREFIX_LEN].copy_from_slice(nonce_prefix);
    nonce[NONCE_PREFIX_LEN..].copy_from_slice(&seq.to_be_bytes());
    nonce
}

/// Seal `plaintext` into a wire frame: `[seq:u64 BE][ciphertext-with-tag]`.
///
/// `seq_value` is the bare counter (low 63 bits); `direction_bit` is either
/// `CALLER_DIRECTION_BIT` (0) or `CALLEE_DIRECTION_BIT` (`1 << 63`). The
/// resulting wire `seq` is `seq_value | direction_bit`. Returns the full
/// wire frame.
pub fn seal_frame(
    seq_value: u64,
    direction_bit: u64,
    key: &[u8; KEY_LEN],
    nonce_prefix: &[u8; NONCE_PREFIX_LEN],
    plaintext: &[u8],
) -> Vec<u8> {
    // Never mask-wrap: a seq >= 2^63 would fold onto a low seq and reuse its
    // AES-GCM nonce on this key+direction. Fail loudly instead.
    assert!(seq_value <= SEQ_VALUE_MASK, "call frame seq out of range");

    let seq = seq_value | direction_bit;
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    let nonce_bytes = build_nonce(nonce_prefix, seq);
    let nonce = Nonce::from_slice(&nonce_bytes);
    // aes-gcm appends the 16-byte tag to the ciphertext, matching the
    // Web Crypto AES-GCM layout the wire frame is specified in.
    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .expect("AES-256-GCM encryption of in-memory plaintext cannot fail");

    let mut frame = Vec::with_capacity(SEQ_LEN + ciphertext.len());
    frame.extend_from_slice(&seq.to_be_bytes());
    frame.extend_from_slice(&ciphertext);
    frame
}

/// Open a wire frame, returning the full wire `seq` (value | direction bit)
/// on success, or an error if the frame is malformed or auth fails.
pub fn open_frame(
    frame: &[u8],
    key: &[u8; KEY_LEN],
    nonce_prefix: &[u8; NONCE_PREFIX_LEN],
) -> Result<u64, FrameCryptoError> {
    let parsed = parse_frame(frame).ok_or(FrameCryptoError::MalformedFrame)?;
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    let nonce_bytes = build_nonce(nonce_prefix, parsed.seq);
    let nonce = Nonce::from_slice(&nonce_bytes);
    match cipher.decrypt(nonce, parsed.ciphertext) {
        Ok(_plaintext) => Ok(parsed.seq),
        Err(_) => Err(FrameCryptoError::AuthFailed),
    }
}

/// Open a wire frame, returning `(seq, payload)` on success.
pub fn open_frame_payload(
    frame: &[u8],
    key: &[u8; KEY_LEN],
    nonce_prefix: &[u8; NONCE_PREFIX_LEN],
) -> Result<(u64, Vec<u8>), FrameCryptoError> {
    let parsed = parse_frame(frame).ok_or(FrameCryptoError::MalformedFrame)?;
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    let nonce_bytes = build_nonce(nonce_prefix, parsed.seq);
    let nonce = Nonce::from_slice(&nonce_bytes);
    let plaintext = cipher
        .decrypt(nonce, parsed.ciphertext)
        .map_err(|_| FrameCryptoError::AuthFailed)?;
    Ok((parsed.seq, plaintext))
}

/// Parse the wire frame header without decrypting. Returns `None` if the
/// frame is shorter than the seq header + a non-empty ciphertext+tag.
pub fn parse_frame(frame: &[u8]) -> Option<ParsedFrame<'_>> {
    if frame.len() < MIN_FRAME_LEN {
        return None;
    }
    let (header, ciphertext) = frame.split_at(SEQ_LEN);
    let mut seq_bytes = [0u8; 8];
    seq_bytes.copy_from_slice(header);
    Some(ParsedFrame {
        seq: u64::from_be_bytes(seq_bytes),
        ciphertext,
    })
}

/// A parsed (still-encrypted) wire frame: seq + ciphertext-with-tag.
#[derive(Debug, Clone, Copy)]
pub struct ParsedFrame<'a> {
    pub seq: u64,
    pub ciphertext: &'a [u8],
}

/// Build a wire frame from a pre-computed seq and ciphertext (test helper).
pub fn build_frame(seq: u64, ciphertext: &[u8]) -> Vec<u8> {
    let mut frame = Vec::with_capacity(SEQ_LEN + ciphertext.len());
    frame.extend_from_slice(&seq.to_be_bytes());
    frame.extend_from_slice(ciphertext);
    frame
}

#[cfg(test)]
mod tests {
    use super::*;

    // KEY_B64 = "AAAA...AAAA==" decodes to 32 zero bytes; PREFIX_B64 =
    // "AAAAAA==" decodes to 4 zero bytes. The tests use all-zero raw bytes
    // directly.
    const KEY: [u8; KEY_LEN] = [0u8; KEY_LEN];
    const PREFIX: [u8; NONCE_PREFIX_LEN] = [0u8; NONCE_PREFIX_LEN];

    #[test]
    fn seals_and_opens_a_frame_with_the_same_key() {
        let payload = [1u8, 2, 3, 4, 5];
        let sealed = seal_frame(7, CALLER_DIRECTION_BIT, &KEY, &PREFIX, &payload);
        let (seq, opened) = open_frame_payload(&sealed, &KEY, &PREFIX).expect("open ok");
        assert_eq!(opened, vec![1, 2, 3, 4, 5]);
        assert_eq!(seq, 7);
    }

    #[test]
    fn rejects_a_tampered_frame() {
        let mut sealed = seal_frame(1, CALLER_DIRECTION_BIT, &KEY, &PREFIX, &[9, 9, 9]);
        let last = sealed.len() - 1;
        sealed[last] ^= 0xff;
        assert_eq!(
            open_frame(&sealed, &KEY, &PREFIX),
            Err(FrameCryptoError::AuthFailed)
        );
    }

    #[test]
    fn build_frame_and_parse_frame_roundtrip_the_seq() {
        let cipher = [1u8, 2, 3];
        let wire = build_frame(42, &cipher);
        let parsed = parse_frame(&wire).expect("parsed");
        assert_eq!(parsed.seq, 42);
        assert_eq!(parsed.ciphertext, &[1u8, 2, 3]);
    }

    #[test]
    fn caller_and_callee_direction_bits_differ() {
        assert_ne!(CALLER_DIRECTION_BIT, CALLEE_DIRECTION_BIT);
        assert_eq!(CALLER_DIRECTION_BIT, 0);
        assert_eq!(CALLEE_DIRECTION_BIT, 1u64 << 63);
    }

    #[test]
    #[should_panic(expected = "call frame seq out of range")]
    fn rejects_a_seq_that_would_overflow_the_63_bit_value_space() {
        // 2^63 masks down to 0 — sealing it would silently reuse seq 0's nonce.
        let _ = seal_frame(1u64 << 63, CALLER_DIRECTION_BIT, &KEY, &PREFIX, &[1]);
    }

    #[test]
    #[should_panic(expected = "call frame seq out of range")]
    fn rejects_a_seq_value_above_the_mask() {
        // u64 has no negative values; the equivalent rejection is any value
        // > SEQ_VALUE_MASK.
        let _ = seal_frame(
            SEQ_VALUE_MASK + 1,
            CALLER_DIRECTION_BIT,
            &KEY,
            &PREFIX,
            &[1],
        );
    }

    #[test]
    fn seq_value_and_direction_bit_combine_into_wire_seq() {
        let sealed = seal_frame(7, CALLEE_DIRECTION_BIT, &KEY, &PREFIX, &[1, 2, 3]);
        let parsed = parse_frame(&sealed).expect("parsed");
        // Wire seq carries the callee direction bit (high bit set).
        assert_eq!(parsed.seq, 7 | CALLEE_DIRECTION_BIT);
        assert_eq!(parsed.seq & SEQ_VALUE_MASK, 7);
        let (seq, _) = open_frame_payload(&sealed, &KEY, &PREFIX).expect("open ok");
        assert_eq!(seq, 7 | CALLEE_DIRECTION_BIT);
    }

    #[test]
    fn nonce_layout_is_prefix_then_seq_big_endian() {
        // The 12-byte nonce is [prefix(4)][seq(8 BE)].
        // seq = 7 (caller) -> nonce = [0,0,0,0, 0,0,0,0,0,0,0,7].
        let prefix = [0xDEu8, 0xAD, 0xBE, 0xEF];
        let nonce = build_nonce(&prefix, 7);
        assert_eq!(&nonce[..4], &[0xDE, 0xAD, 0xBE, 0xEF]);
        assert_eq!(nonce[4..], [0, 0, 0, 0, 0, 0, 0, 7]);
    }

    #[test]
    fn caller_and_callee_seal_with_distinct_nonces_for_same_seq_value() {
        // The two directions must never collide nonces while sharing one key.
        // Distinct wire seq -> distinct nonce; both decrypt back to their seq.
        let a = seal_frame(5, CALLER_DIRECTION_BIT, &KEY, &PREFIX, &[10]);
        let b = seal_frame(5, CALLEE_DIRECTION_BIT, &KEY, &PREFIX, &[20]);
        let pa = parse_frame(&a).expect("a");
        let pb = parse_frame(&b).expect("b");
        assert_ne!(pa.seq, pb.seq);
        assert_eq!(open_frame(&a, &KEY, &PREFIX), Ok(5));
        assert_eq!(open_frame(&b, &KEY, &PREFIX), Ok(5 | CALLEE_DIRECTION_BIT));
    }

    #[test]
    fn open_frame_rejects_a_truncated_header() {
        // Less than MIN_FRAME_LEN (9) -> MalformedFrame, never touches the cipher.
        let stub = [0u8; 8];
        assert_eq!(
            open_frame(&stub, &KEY, &PREFIX),
            Err(FrameCryptoError::MalformedFrame)
        );
    }
}
