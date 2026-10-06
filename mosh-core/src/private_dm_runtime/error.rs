//! Native error conversions used by the DM runtime.

use super::*;

impl std::fmt::Display for PrivateDmRuntimeError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::PayloadTooLarge => write!(
                formatter,
                "message metadata exceeds the network payload limit"
            ),
            Self::Deletion(error) => error.fmt(formatter),
            Self::Revoked => write!(formatter, "this installation's DM membership was revoked"),
            Self::Moss(error) => write!(formatter, "Moss error: {error}"),
            Self::OpenMls(error) => write!(formatter, "OpenMLS error: {error}"),
            Self::Codec(error) => write!(formatter, "codec error: {error}"),
            Self::InvalidInvite(error) => write!(formatter, "invalid invite: {error}"),
            Self::NotReady => write!(formatter, "private DM session is not ready"),
            Self::MissingSession => write!(formatter, "private DM session is missing"),
            Self::MissingMessage(id) => write!(formatter, "private DM message is missing: {id}"),
            Self::DuplicateSession(id) => {
                write!(formatter, "private DM session already exists: {id}")
            }
            Self::Attachment(error) => write!(formatter, "attachment error: {error}"),
            Self::MissingAttachment(id) => {
                write!(formatter, "attachment not found: {id}")
            }
            Self::Persistence(error) => {
                write!(formatter, "persistence error: {error}")
            }
        }
    }
}

impl std::error::Error for PrivateDmRuntimeError {}

impl From<MlsCryptoError> for PrivateDmRuntimeError {
    fn from(error: MlsCryptoError) -> Self {
        match error {
            MlsCryptoError::OpenMls(message) => Self::OpenMls(message),
            MlsCryptoError::Codec(message) => Self::Codec(message),
            MlsCryptoError::NotReady => Self::NotReady,
        }
    }
}

impl From<crate::conversation::transfer::TransferError> for PrivateDmRuntimeError {
    fn from(error: crate::conversation::transfer::TransferError) -> Self {
        match error {
            crate::conversation::transfer::TransferError::Bytes(message) => {
                Self::Attachment(message)
            }
            crate::conversation::transfer::TransferError::Slot(error) => error.into(),
        }
    }
}

impl From<LogError> for PrivateDmRuntimeError {
    fn from(error: LogError) -> Self {
        match error {
            LogError::Missing(id) => Self::MissingMessage(id),
            LogError::Codec(error) => Self::Codec(error),
        }
    }
}

impl From<crate::conversation::attachments::SlotError> for PrivateDmRuntimeError {
    fn from(error: crate::conversation::attachments::SlotError) -> Self {
        match error {
            crate::conversation::attachments::SlotError::Missing(id) => Self::MissingAttachment(id),
            other => Self::Attachment(other.to_string()),
        }
    }
}

impl From<crate::persistence::PersistenceError> for PrivateDmRuntimeError {
    fn from(error: crate::persistence::PersistenceError) -> Self {
        Self::Persistence(error.to_string())
    }
}
