//! The group error and its conversions.

use super::*;

#[derive(Debug)]
pub enum PrivateGroupError {
    Moss(String),
    Codec(String),
    OpenMls(String),
    InvalidInvite(String),
    BodyTooLarge,
    MissingGroup(String),
    MissingMessage(String),
    DuplicateGroup(String),
    NotReady,
    Attachment(String),
    MissingAttachment(String),
}

impl std::fmt::Display for PrivateGroupError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Moss(error) => write!(formatter, "Moss error: {error}"),
            Self::Codec(error) => write!(formatter, "codec error: {error}"),
            Self::OpenMls(error) => write!(formatter, "OpenMLS error: {error}"),
            Self::InvalidInvite(error) => write!(formatter, "invalid group invite: {error}"),
            Self::BodyTooLarge => write!(formatter, "group message too large"),
            Self::MissingGroup(id) => write!(formatter, "group not joined: {id}"),
            Self::MissingMessage(id) => write!(formatter, "group message missing: {id}"),
            Self::DuplicateGroup(id) => write!(formatter, "already joined group: {id}"),
            Self::NotReady => write!(formatter, "group not ready"),
            Self::Attachment(error) => write!(formatter, "attachment error: {error}"),
            Self::MissingAttachment(id) => write!(formatter, "attachment not found: {id}"),
        }
    }
}

impl std::error::Error for PrivateGroupError {}

impl From<MlsCryptoError> for PrivateGroupError {
    fn from(error: MlsCryptoError) -> Self {
        match error {
            MlsCryptoError::OpenMls(message) => Self::OpenMls(message),
            MlsCryptoError::Codec(message) => Self::Codec(message),
            MlsCryptoError::NotReady => Self::NotReady,
        }
    }
}

impl From<TransferError> for PrivateGroupError {
    fn from(error: TransferError) -> Self {
        match error {
            TransferError::Bytes(message) => Self::Attachment(message),
            TransferError::Slot(error) => error.into(),
        }
    }
}

impl From<LogError> for PrivateGroupError {
    fn from(error: LogError) -> Self {
        match error {
            LogError::Missing(id) => Self::MissingMessage(id),
            LogError::Codec(error) => Self::Codec(error),
        }
    }
}

impl From<SlotError> for PrivateGroupError {
    fn from(error: SlotError) -> Self {
        match error {
            SlotError::Missing(id) => Self::MissingAttachment(id),
            other => Self::Attachment(other.to_string()),
        }
    }
}
