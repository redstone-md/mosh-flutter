//! A native action target has one immutable semantic occurrence.
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct Occurrence {
    pub native_id: String,
    pub row_key: String,
    pub identity: String,
    /// None is reserved for a locally verified erased target.
    pub content_digest: Option<String>,
}
