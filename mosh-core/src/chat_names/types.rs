use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize)]
pub struct ChatNameEntry {
    pub conversation_key: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ChatNameSnapshot {
    pub entries: Vec<ChatNameEntry>,
    pub pending: bool,
    pub can_rename: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChatNameErrorKind {
    InvalidInput,
    Storage,
    Unauthorized,
    Unavailable,
}

#[derive(Debug, Clone)]
pub struct ChatNameError {
    pub kind: ChatNameErrorKind,
    pub message: String,
}

impl ChatNameError {
    pub(crate) fn new(kind: ChatNameErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
        }
    }

    pub(crate) fn storage(error: impl std::fmt::Display) -> Self {
        Self::new(ChatNameErrorKind::Storage, error.to_string())
    }

    pub(crate) fn invalid() -> Self {
        Self::new(
            ChatNameErrorKind::InvalidInput,
            "invalid chat name or version",
        )
    }
}

impl std::fmt::Display for ChatNameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for ChatNameError {}

impl From<crate::device_link::types::DeviceLinkError> for ChatNameError {
    fn from(error: crate::device_link::types::DeviceLinkError) -> Self {
        use crate::device_link::types::DeviceLinkErrorKind;
        let kind = match error.kind {
            DeviceLinkErrorKind::Storage => ChatNameErrorKind::Storage,
            DeviceLinkErrorKind::InvalidRoster => ChatNameErrorKind::Unauthorized,
            _ => ChatNameErrorKind::Unavailable,
        };
        Self::new(kind, error.message)
    }
}

pub type Result<T> = std::result::Result<T, ChatNameError>;

/// A Lamport counter plus a stable writer id gives every replica the same order.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) struct NameVersion {
    pub counter: u64,
    pub actor: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct NameRecord {
    pub key: String,
    pub version: NameVersion,
    pub name: Option<String>,
}

/// Validate instead of truncating. Scalar counting matches existing group names.
pub fn validate_chat_name(value: &str) -> Result<String> {
    let name = value.trim();
    if name.is_empty()
        || name.chars().count() > 64
        || name
            .chars()
            .any(|c| c.is_control() || matches!(c, '\u{2028}' | '\u{2029}'))
    {
        return Err(ChatNameError::invalid());
    }
    Ok(name.to_owned())
}

pub(crate) fn validate_key(key: &str) -> Result<()> {
    match key.split_once(':') {
        Some(("dm" | "channel", id))
            if !id.is_empty() && id.len() <= 256 && !id.chars().any(char::is_control) =>
        {
            Ok(())
        }
        _ => Err(ChatNameError::invalid()),
    }
}

impl NameRecord {
    pub(crate) fn validate(&self) -> Result<()> {
        validate_key(&self.key)?;
        if self.version.counter == 0
            || self.version.actor.is_empty()
            || self.version.actor.len() > 128
        {
            return Err(ChatNameError::invalid());
        }
        if let Some(name) = &self.name {
            if validate_chat_name(name)? != *name {
                return Err(ChatNameError::invalid());
            }
        }
        Ok(())
    }
}
