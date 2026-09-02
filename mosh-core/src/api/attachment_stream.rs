//! Unified attachment range bridge for the local media server.

use flutter_rust_bridge::frb;

use crate::attachment_runtime::StreamRange;

/// The state of one attachment range request.
#[frb(non_opaque)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AttachmentStreamState {
    Ready,
    Pending,
    Unknown,
}

/// One bridge-friendly range response shape for all conversation kinds.
/// Only the fields relevant to [state] are populated. A flat DTO avoids a
/// generated Dart union dependency for this narrow polling protocol.
#[frb(non_opaque)]
#[derive(Clone, Debug)]
pub struct AttachmentStreamRange {
    pub state: AttachmentStreamState,
    pub bytes: Vec<u8>,
    pub total_size: u64,
    pub mime: String,
}

impl From<StreamRange> for AttachmentStreamRange {
    fn from(value: StreamRange) -> Self {
        match value {
            StreamRange::Ready {
                bytes,
                total_size,
                mime,
            } => Self {
                state: AttachmentStreamState::Ready,
                bytes,
                total_size,
                mime,
            },
            StreamRange::Pending { total_size } => Self {
                state: AttachmentStreamState::Pending,
                bytes: Vec::new(),
                total_size,
                mime: String::new(),
            },
            StreamRange::Unknown => Self {
                state: AttachmentStreamState::Unknown,
                bytes: Vec::new(),
                total_size: 0,
                mime: String::new(),
            },
        }
    }
}

/// Serves one decrypted attachment range through the owning conversation
/// runtime. The three runtime implementations remain the source of truth.
pub fn stream_attachment_range(
    kind: String,
    host: String,
    attachment_id: String,
    start: u64,
    end: u64,
) -> Result<AttachmentStreamRange, String> {
    let range = match kind.as_str() {
        "dm" => crate::api::private_dm::ensure_runtime()
            .map_err(|error| error.to_string())?
            .as_mut()
            .expect("ensure_runtime guarantees Some")
            .stream_attachment_range(&host, &attachment_id, start, end)
            .map_err(|error| error.to_string())?,
        "channel" => crate::api::channel::ensure_runtime()
            .map_err(|error| error.to_string())?
            .as_mut()
            .expect("ensure_runtime guarantees Some")
            .stream_attachment_range(&host, &attachment_id, start, end)
            .map_err(|error| error.to_string())?,
        "group" => crate::api::private_group::ensure_runtime()
            .map_err(|error| error.to_string())?
            .as_mut()
            .expect("ensure_runtime guarantees Some")
            .stream_attachment_range(&host, &attachment_id, start, end)
            .map_err(|error| error.to_string())?,
        _ => return Err("unknown stream kind".to_string()),
    };
    Ok(range.into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_runtime_range_states_to_one_bridge_shape() {
        let ready = AttachmentStreamRange::from(StreamRange::Ready {
            bytes: vec![1, 2, 3],
            total_size: 9,
            mime: "audio/ogg".to_string(),
        });
        assert_eq!(ready.state, AttachmentStreamState::Ready);
        assert_eq!(ready.bytes, vec![1, 2, 3]);
        assert_eq!(ready.total_size, 9);
        assert_eq!(ready.mime, "audio/ogg");

        let pending = AttachmentStreamRange::from(StreamRange::Pending { total_size: 9 });
        assert_eq!(pending.state, AttachmentStreamState::Pending);
        assert!(pending.bytes.is_empty());
        assert_eq!(pending.total_size, 9);
        assert!(pending.mime.is_empty());

        let unknown = AttachmentStreamRange::from(StreamRange::Unknown);
        assert_eq!(unknown.state, AttachmentStreamState::Unknown);
        assert!(unknown.bytes.is_empty());
        assert_eq!(unknown.total_size, 0);
        assert!(unknown.mime.is_empty());
    }

    #[test]
    fn rejects_unknown_conversation_kind_before_runtime_access() {
        let error = stream_attachment_range(
            "mesh".to_string(),
            "host".to_string(),
            "attachment".to_string(),
            0,
            1,
        )
        .unwrap_err();
        assert_eq!(error, "unknown stream kind");
    }
}
