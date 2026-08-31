//! The error contract shared by the conversation bridge.
//!
//! Conversation runtimes keep their detailed, kind-specific errors. This
//! module maps them into the smaller actionable category that the Dart caller
//! needs. It is a seam contract, not a fourth runtime error hierarchy.
//!
//! Nothing returns this yet. The six shared bridge actions in ADR 0024 will
//! return it when they land, rather than retrofitting a typed error over a
//! flattened string afterwards.

use flutter_rust_bridge::frb;

use crate::channel_runtime::ChannelRuntimeError;
use crate::org_runtime::OrgError;
use crate::private_dm_runtime::PrivateDmRuntimeError;
use crate::private_group_runtime::PrivateGroupError;

/// What the caller can do about a failed conversation action.
#[frb(non_opaque)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConversationBridgeErrorKind {
    /// The request was wrong; editing it may help.
    InvalidInput,
    /// The node, mesh, or signing identity is unavailable; try later.
    Unavailable,
    /// The conversation is still setting up; wait for it to become ready.
    NotReady,
    /// We are not in this conversation any more.
    MissingConversation,
    /// The requested message does not exist.
    MissingMessage,
    /// The requested attachment does not exist.
    MissingAttachment,
    /// A transfer failed and can be retried from the start.
    Transfer,
    /// The encrypted store or its keychain failed; retrying cannot repair it.
    Persistence,
    /// The MLS history cannot be bridged; the member must rejoin.
    NeedsRejoin,
    /// The member's credential is no longer valid in this conversation.
    Revoked,
    /// No caller-visible remedy exists for this failure.
    Internal,
}

/// One failed conversation action, as the seam reports it.
///
/// `kind` is the contract. `message` is diagnostic text; callers must not
/// branch on it because it is rendered by the runtime that produced it.
#[frb(non_opaque)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConversationBridgeError {
    pub kind: ConversationBridgeErrorKind,
    pub message: String,
}

impl ConversationBridgeError {
    pub fn new(kind: ConversationBridgeErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
        }
    }
}

impl std::fmt::Display for ConversationBridgeError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for ConversationBridgeError {}

/// The DM runtime already keeps `Persistence` distinct for ADR 0011's
/// fail-closed path. Keep that distinction at the bridge too.
impl From<PrivateDmRuntimeError> for ConversationBridgeError {
    fn from(error: PrivateDmRuntimeError) -> Self {
        let kind = match &error {
            PrivateDmRuntimeError::Moss(_) => ConversationBridgeErrorKind::Unavailable,
            PrivateDmRuntimeError::OpenMls(_) => ConversationBridgeErrorKind::Internal,
            PrivateDmRuntimeError::Codec(_) => ConversationBridgeErrorKind::Internal,
            PrivateDmRuntimeError::InvalidInvite(_) => ConversationBridgeErrorKind::InvalidInput,
            PrivateDmRuntimeError::NotReady => ConversationBridgeErrorKind::NotReady,
            PrivateDmRuntimeError::MissingSession => {
                ConversationBridgeErrorKind::MissingConversation
            }
            PrivateDmRuntimeError::MissingMessage(_) => ConversationBridgeErrorKind::MissingMessage,
            PrivateDmRuntimeError::DuplicateSession(_) => ConversationBridgeErrorKind::InvalidInput,
            PrivateDmRuntimeError::Attachment(_) => ConversationBridgeErrorKind::Transfer,
            PrivateDmRuntimeError::MissingAttachment(_) => {
                ConversationBridgeErrorKind::MissingAttachment
            }
            PrivateDmRuntimeError::Persistence(_) => ConversationBridgeErrorKind::Persistence,
        };
        Self::new(kind, error.to_string())
    }
}

impl From<ChannelRuntimeError> for ConversationBridgeError {
    fn from(error: ChannelRuntimeError) -> Self {
        let kind = match &error {
            ChannelRuntimeError::Moss(_) => ConversationBridgeErrorKind::Unavailable,
            ChannelRuntimeError::Codec(_) => ConversationBridgeErrorKind::Internal,
            ChannelRuntimeError::InvalidName(_) => ConversationBridgeErrorKind::InvalidInput,
            ChannelRuntimeError::BodyTooLarge => ConversationBridgeErrorKind::InvalidInput,
            ChannelRuntimeError::MissingChannel(_) => {
                ConversationBridgeErrorKind::MissingConversation
            }
            ChannelRuntimeError::MissingMessage(_) => ConversationBridgeErrorKind::MissingMessage,
            ChannelRuntimeError::DuplicateChannel(_) => ConversationBridgeErrorKind::InvalidInput,
            ChannelRuntimeError::Attachment(_) => ConversationBridgeErrorKind::Transfer,
            ChannelRuntimeError::MissingAttachment(_) => {
                ConversationBridgeErrorKind::MissingAttachment
            }
        };
        Self::new(kind, error.to_string())
    }
}

impl From<PrivateGroupError> for ConversationBridgeError {
    fn from(error: PrivateGroupError) -> Self {
        let kind = match &error {
            PrivateGroupError::Moss(_) => ConversationBridgeErrorKind::Unavailable,
            PrivateGroupError::Codec(_) => ConversationBridgeErrorKind::Internal,
            PrivateGroupError::OpenMls(_) => ConversationBridgeErrorKind::Internal,
            PrivateGroupError::InvalidInvite(_) => ConversationBridgeErrorKind::InvalidInput,
            PrivateGroupError::BodyTooLarge => ConversationBridgeErrorKind::InvalidInput,
            PrivateGroupError::MissingGroup(_) => ConversationBridgeErrorKind::MissingConversation,
            PrivateGroupError::MissingMessage(_) => ConversationBridgeErrorKind::MissingMessage,
            PrivateGroupError::DuplicateGroup(_) => ConversationBridgeErrorKind::InvalidInput,
            PrivateGroupError::NotReady => ConversationBridgeErrorKind::NotReady,
            PrivateGroupError::Attachment(_) => ConversationBridgeErrorKind::Transfer,
            PrivateGroupError::MissingAttachment(_) => {
                ConversationBridgeErrorKind::MissingAttachment
            }
        };
        Self::new(kind, error.to_string())
    }
}

impl From<OrgError> for ConversationBridgeError {
    fn from(error: OrgError) -> Self {
        let kind = match &error {
            OrgError::InvalidBundle(_) => ConversationBridgeErrorKind::InvalidInput,
            OrgError::Duplicate(_) => ConversationBridgeErrorKind::InvalidInput,
            OrgError::NotJoined(_) => ConversationBridgeErrorKind::MissingConversation,
            OrgError::IdentityUnavailable => ConversationBridgeErrorKind::Unavailable,
            OrgError::Moss(_) => ConversationBridgeErrorKind::Unavailable,
            OrgError::Persistence(_) => ConversationBridgeErrorKind::Persistence,
            OrgError::Codec(_) => ConversationBridgeErrorKind::Internal,
        };
        Self::new(kind, error.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    type Kind = ConversationBridgeErrorKind;

    fn assert_maps(
        error: impl std::fmt::Display + Into<ConversationBridgeError>,
        expected_kind: Kind,
    ) {
        let expected_message = error.to_string();
        let bridge: ConversationBridgeError = error.into();
        assert_eq!(bridge.kind, expected_kind);
        assert_eq!(bridge.message, expected_message);
    }

    #[test]
    fn maps_every_dm_failure_to_an_actionable_category() {
        assert_maps(
            PrivateDmRuntimeError::Moss("node down".into()),
            Kind::Unavailable,
        );
        assert_maps(
            PrivateDmRuntimeError::OpenMls("bad epoch".into()),
            Kind::Internal,
        );
        assert_maps(
            PrivateDmRuntimeError::Codec("base64".into()),
            Kind::Internal,
        );
        assert_maps(
            PrivateDmRuntimeError::InvalidInvite("no fragment".into()),
            Kind::InvalidInput,
        );
        assert_maps(PrivateDmRuntimeError::NotReady, Kind::NotReady);
        assert_maps(
            PrivateDmRuntimeError::MissingSession,
            Kind::MissingConversation,
        );
        assert_maps(
            PrivateDmRuntimeError::MissingMessage("m-1".into()),
            Kind::MissingMessage,
        );
        assert_maps(
            PrivateDmRuntimeError::DuplicateSession("host".into()),
            Kind::InvalidInput,
        );
        assert_maps(
            PrivateDmRuntimeError::Attachment("store".into()),
            Kind::Transfer,
        );
        assert_maps(
            PrivateDmRuntimeError::MissingAttachment("a-1".into()),
            Kind::MissingAttachment,
        );
        assert_maps(
            PrivateDmRuntimeError::Persistence("dek unavailable".into()),
            Kind::Persistence,
        );
    }

    #[test]
    fn maps_every_channel_failure_to_an_actionable_category() {
        assert_maps(
            ChannelRuntimeError::Moss("node down".into()),
            Kind::Unavailable,
        );
        assert_maps(ChannelRuntimeError::Codec("base64".into()), Kind::Internal);
        assert_maps(
            ChannelRuntimeError::InvalidName("".into()),
            Kind::InvalidInput,
        );
        assert_maps(ChannelRuntimeError::BodyTooLarge, Kind::InvalidInput);
        assert_maps(
            ChannelRuntimeError::MissingChannel("general".into()),
            Kind::MissingConversation,
        );
        assert_maps(
            ChannelRuntimeError::MissingMessage("m-1".into()),
            Kind::MissingMessage,
        );
        assert_maps(
            ChannelRuntimeError::DuplicateChannel("general".into()),
            Kind::InvalidInput,
        );
        assert_maps(
            ChannelRuntimeError::Attachment("store".into()),
            Kind::Transfer,
        );
        assert_maps(
            ChannelRuntimeError::MissingAttachment("a-1".into()),
            Kind::MissingAttachment,
        );
    }

    #[test]
    fn maps_every_group_failure_to_an_actionable_category() {
        assert_maps(
            PrivateGroupError::Moss("node down".into()),
            Kind::Unavailable,
        );
        assert_maps(PrivateGroupError::Codec("base64".into()), Kind::Internal);
        assert_maps(PrivateGroupError::OpenMls("no leaf".into()), Kind::Internal);
        assert_maps(
            PrivateGroupError::InvalidInvite("no fragment".into()),
            Kind::InvalidInput,
        );
        assert_maps(PrivateGroupError::BodyTooLarge, Kind::InvalidInput);
        assert_maps(
            PrivateGroupError::MissingGroup("g-1".into()),
            Kind::MissingConversation,
        );
        assert_maps(
            PrivateGroupError::MissingMessage("m-1".into()),
            Kind::MissingMessage,
        );
        assert_maps(
            PrivateGroupError::DuplicateGroup("g-1".into()),
            Kind::InvalidInput,
        );
        assert_maps(PrivateGroupError::NotReady, Kind::NotReady);
        assert_maps(
            PrivateGroupError::Attachment("store".into()),
            Kind::Transfer,
        );
        assert_maps(
            PrivateGroupError::MissingAttachment("a-1".into()),
            Kind::MissingAttachment,
        );
    }

    #[test]
    fn maps_every_org_failure_to_an_actionable_category() {
        assert_maps(
            OrgError::InvalidBundle("not a mosh://org URI".into()),
            Kind::InvalidInput,
        );
        assert_maps(OrgError::Duplicate("acme".into()), Kind::InvalidInput);
        assert_maps(
            OrgError::NotJoined("acme".into()),
            Kind::MissingConversation,
        );
        assert_maps(OrgError::IdentityUnavailable, Kind::Unavailable);
        assert_maps(OrgError::Moss("node down".into()), Kind::Unavailable);
        assert_maps(OrgError::Persistence("redb".into()), Kind::Persistence);
        assert_maps(OrgError::Codec("json".into()), Kind::Internal);
    }

    /// ADR 0011's fail-closed path must not look like a transient mesh error.
    #[test]
    fn persistence_is_never_folded_into_unavailable() {
        let dm = ConversationBridgeError::from(PrivateDmRuntimeError::Persistence("dek".into()));
        let org = ConversationBridgeError::from(OrgError::Persistence("redb".into()));
        assert_eq!(dm.kind, Kind::Persistence);
        assert_eq!(org.kind, Kind::Persistence);
        assert_ne!(dm.kind, Kind::Unavailable);
        assert_ne!(org.kind, Kind::Unavailable);
    }

    #[test]
    fn display_is_the_message_and_the_kind_is_kept_separate() {
        let bridge =
            ConversationBridgeError::new(Kind::MissingAttachment, "attachment not found: a-1");
        assert_eq!(bridge.to_string(), "attachment not found: a-1");
        assert_eq!(bridge.kind, Kind::MissingAttachment);
    }

    #[test]
    fn a_hand_built_error_round_trips_through_the_error_trait() {
        let bridge = ConversationBridgeError::new(Kind::NeedsRejoin, "epoch gap");
        let as_error: &dyn std::error::Error = &bridge;
        assert_eq!(as_error.to_string(), "epoch gap");
    }
}
