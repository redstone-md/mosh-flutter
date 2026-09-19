use serde::{Deserialize, Serialize};

use super::contracts::PrivateDmRuntimeError;
use crate::attachment_runtime::{ChunkFrame, ChunkRequest};

pub const CONTROL_CHANNEL_PREFIX: &str = "mls-control/";
pub const DATA_CHANNEL_PREFIX: &str = "mls-data/";
pub const BLOB_CHANNEL_PREFIX: &str = "mls-blob/";
pub const VOICE_CALL_CHANNEL_PREFIX: &str = "voice-call/";

pub fn control_channel(session_id: &str) -> String {
    format!("{CONTROL_CHANNEL_PREFIX}{session_id}")
}

pub fn data_channel(session_id: &str) -> String {
    format!("{DATA_CHANNEL_PREFIX}{session_id}")
}

pub fn blob_channel(session_id: &str) -> String {
    format!("{BLOB_CHANNEL_PREFIX}{session_id}")
}

pub fn voice_call_channel(call_id: &str) -> String {
    format!("{VOICE_CALL_CHANNEL_PREFIX}{call_id}")
}

pub fn channel_session_id(channel: &str) -> Option<&str> {
    channel
        .strip_prefix(CONTROL_CHANNEL_PREFIX)
        .or_else(|| channel.strip_prefix(DATA_CHANNEL_PREFIX))
        .or_else(|| channel.strip_prefix(BLOB_CHANNEL_PREFIX))
}

pub fn channel_call_id(channel: &str) -> Option<&str> {
    channel.strip_prefix(VOICE_CALL_CHANNEL_PREFIX)
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ControlEnvelope {
    KeyPackage {
        session_id: String,
        participant_id: String,
        from_device: String,
        key_package_b64: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        moss_peer_id: Option<String>,
    },
    Welcome {
        session_id: String,
        participant_id: String,
        from_device: String,
        welcome_b64: String,
        ratchet_tree_b64: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        moss_peer_id: Option<String>,
    },
    /// Carries an AttachmentManifest encrypted as an MLS application message,
    /// so the per-attachment AES key never crosses the wire in the clear.
    AttachmentManifest {
        session_id: String,
        participant_id: String,
        from_device: String,
        manifest_ciphertext_b64: String,
    },
    /// Initiates a 1:1 voice call. The body — a JSON object carrying the
    /// per-call AES-GCM key and the 4-byte nonce prefix — is encrypted as an
    /// MLS application message so the key never crosses the wire in the
    /// clear.
    CallOffer {
        session_id: String,
        participant_id: String,
        from_device: String,
        call_id: String,
        offer_ciphertext_b64: String,
    },
    /// Re-announces the sender's moss peer id to a counterpart that has lost
    /// it. The id otherwise rides only KeyPackage/Welcome, which stop once the
    /// handshake completes, so a session restored from a record written before
    /// the id was known could never relearn it and stayed unable to tell its
    /// peer from a stranger. Carries no secret: the moss id is a public key,
    /// published in the clear in the invite URI. Old clients fail to decode the
    /// unknown variant and drop the frame -- they simply never re-announce.
    PeerAnnounce {
        session_id: String,
        participant_id: String,
        from_device: String,
        moss_peer_id: String,
    },
    CallAccept {
        session_id: String,
        participant_id: String,
        call_id: String,
    },
    CallDecline {
        session_id: String,
        participant_id: String,
        call_id: String,
        reason: String,
    },
    CallEnd {
        session_id: String,
        participant_id: String,
        call_id: String,
        reason: String,
    },
    /// "I am here and I hold the group." Sent by each side as soon as its MLS
    /// state is ready, repeated until the counterpart answers with any
    /// authenticated frame. The body is the sender's moss peer id,
    /// MLS-encrypted, so receiving one is proof the counterpart is alive and
    /// nobody else can fake it. Old clients fail to decode the unknown
    /// variant and drop the frame — they simply never say hello.
    Hello {
        session_id: String,
        participant_id: String,
        from_device: String,
        hello_ciphertext_b64: String,
    },
    /// Receipt for one Data message: the receiving runtime stored (or already
    /// had) the message. The acked message id travels MLS-encrypted — a
    /// plaintext ack could be forged by anyone on the pubsub mesh to fake
    /// delivery and silence the auto-resend loop; only the MLS peer can
    /// produce a ciphertext that decrypts. Old clients fail to decode the
    /// unknown variant and drop the frame — harmless, they simply never ack.
    DeliveryAck {
        session_id: String,
        participant_id: String,
        ack_ciphertext_b64: String,
    },
    /// Liveness hint published while the sender types. The body — a JSON
    /// object naming the device and the sender-claimed expiry — travels
    /// MLS-encrypted, so a mesh bystander cannot forge "someone is typing";
    /// only the MLS peer can produce a ciphertext this group accepts. The
    /// sender repeats it on the refresh cadence while input continues and
    /// simply stops when input ends; the receiver owns the expiry. Old
    /// clients fail to decode the unknown variant and drop the frame —
    /// they simply never show typing.
    TypingIndicator {
        session_id: String,
        participant_id: String,
        from_device: String,
        typing_ciphertext_b64: String,
    },
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DataEnvelope {
    pub session_id: String,
    pub participant_id: String,
    pub from_device: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sent_at_ms: Option<u64>,
    pub ciphertext_b64: String,
    /// Auto-resend counter. Only purpose: make each re-send's bytes differ
    /// from the original so the receiver's frame-level sha256 dedup lets the
    /// duplicate through to the message-id re-ack path. Old clients ignore
    /// the unknown field; their MLS decrypt of the replayed ciphertext fails
    /// (forward secrecy) and the frame is dropped with a logged error.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resend: Option<u32>,
}

/// Traffic on the dedicated blob channel. Chunk payloads are already
/// AES-GCM encrypted by the attachment runtime, so this envelope stays
/// plaintext and only routes requests and ciphertext chunks.
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum BlobEnvelope {
    Request {
        participant_id: String,
        request: ChunkRequest,
    },
    Chunk {
        participant_id: String,
        frame: ChunkFrame,
    },
}

pub fn decode_json<T: for<'de> Deserialize<'de>>(bytes: &[u8]) -> Result<T, PrivateDmRuntimeError> {
    serde_json::from_slice(bytes).map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChannelKind {
    Control,
    Data,
    Blob,
}

impl ChannelKind {
    pub fn channel_for(&self, session_id: &str) -> String {
        match self {
            ChannelKind::Control => control_channel(session_id),
            ChannelKind::Data => data_channel(session_id),
            ChannelKind::Blob => blob_channel(session_id),
        }
    }
}

#[cfg(test)]
pub fn fail_next_test_publish(message: &str) -> crate::moss_ffi::TestPublishFailureGuard {
    crate::moss_ffi::fail_next_test_publish(message)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn call_offer_roundtrip() {
        let envelope = ControlEnvelope::CallOffer {
            session_id: "s".into(),
            participant_id: "p".into(),
            from_device: "d".into(),
            call_id: "c".into(),
            offer_ciphertext_b64: "Y2lwaGVy".into(),
        };
        let json = serde_json::to_string(&envelope).expect("ser");
        let back: ControlEnvelope = serde_json::from_str(&json).expect("de");
        match back {
            ControlEnvelope::CallOffer {
                call_id,
                offer_ciphertext_b64,
                ..
            } => {
                assert_eq!(call_id, "c");
                assert_eq!(offer_ciphertext_b64, "Y2lwaGVy");
            }
            _ => panic!("expected CallOffer"),
        }
    }

    #[test]
    fn call_lifecycle_variants_roundtrip() {
        let accept = ControlEnvelope::CallAccept {
            session_id: "s".into(),
            participant_id: "p".into(),
            call_id: "c".into(),
        };
        let bytes = serde_json::to_vec(&accept).unwrap();
        assert!(matches!(
            serde_json::from_slice::<ControlEnvelope>(&bytes).unwrap(),
            ControlEnvelope::CallAccept { .. }
        ));

        let decline = ControlEnvelope::CallDecline {
            session_id: "s".into(),
            participant_id: "p".into(),
            call_id: "c".into(),
            reason: "busy".into(),
        };
        let bytes = serde_json::to_vec(&decline).unwrap();
        assert!(matches!(
            serde_json::from_slice::<ControlEnvelope>(&bytes).unwrap(),
            ControlEnvelope::CallDecline { .. }
        ));

        let end = ControlEnvelope::CallEnd {
            session_id: "s".into(),
            participant_id: "p".into(),
            call_id: "c".into(),
            reason: "hangup".into(),
        };
        let bytes = serde_json::to_vec(&end).unwrap();
        assert!(matches!(
            serde_json::from_slice::<ControlEnvelope>(&bytes).unwrap(),
            ControlEnvelope::CallEnd { .. }
        ));
    }

    #[test]
    fn key_package_carries_optional_moss_peer_id() {
        let with = ControlEnvelope::KeyPackage {
            session_id: "s".into(),
            participant_id: "p".into(),
            from_device: "d".into(),
            key_package_b64: "a2V5".into(),
            moss_peer_id: Some("ab".repeat(32)),
        };
        let json = serde_json::to_string(&with).unwrap();
        assert!(json.contains(&"ab".repeat(32)));
        let back: ControlEnvelope = serde_json::from_str(&json).unwrap();
        assert!(matches!(
            back,
            ControlEnvelope::KeyPackage {
                moss_peer_id: Some(_),
                ..
            }
        ));

        // Old peers omit the field entirely — must still decode (None).
        let legacy = r#"{"type":"KeyPackage","session_id":"s","participant_id":"p","from_device":"d","key_package_b64":"a2V5"}"#;
        let back: ControlEnvelope = serde_json::from_str(legacy).unwrap();
        assert!(matches!(
            back,
            ControlEnvelope::KeyPackage {
                moss_peer_id: None,
                ..
            }
        ));
    }

    #[test]
    fn channel_kind_names_the_session_channel() {
        assert_eq!(ChannelKind::Control.channel_for("s"), control_channel("s"));
        assert_eq!(ChannelKind::Data.channel_for("s"), data_channel("s"));
        assert_eq!(ChannelKind::Blob.channel_for("s"), blob_channel("s"));
    }

    // An older build drops a control kind it does not know, so a Hello must
    // decode on a build that knows it and nothing else about it matters.
    #[test]
    fn hello_roundtrips() {
        let hello = ControlEnvelope::Hello {
            session_id: "s".into(),
            participant_id: "p".into(),
            from_device: "d".into(),
            hello_ciphertext_b64: "Y2lwaGVy".into(),
        };
        let bytes = serde_json::to_vec(&hello).unwrap();
        assert!(matches!(
            serde_json::from_slice::<ControlEnvelope>(&bytes).unwrap(),
            ControlEnvelope::Hello { .. }
        ));
    }

    #[test]
    fn voice_call_channel_uses_a_distinct_prefix() {
        let channel = voice_call_channel("call-xyz");
        assert_eq!(channel, "voice-call/call-xyz");
        assert_eq!(channel_call_id(&channel), Some("call-xyz"));
        assert!(channel_session_id(&channel).is_none());
        assert!(channel_call_id(&control_channel("s")).is_none());
        assert!(channel_call_id(&data_channel("s")).is_none());
        assert!(channel_call_id(&blob_channel("s")).is_none());
    }
}
