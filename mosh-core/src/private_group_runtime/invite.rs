//! Group invite parsing, labels and URI construction.

use super::*;

pub(super) struct ParsedGroupInvite {
    pub(super) mesh_id: String,
    pub(super) group_id: String,
    pub(super) creator_fingerprint: String,
    pub(super) label: Option<String>,
}

impl ParsedGroupInvite {
    pub(super) fn parse(raw: &str) -> Result<Self, PrivateGroupError> {
        let url = url::Url::parse(raw)
            .map_err(|error| PrivateGroupError::InvalidInvite(error.to_string()))?;
        if url.scheme() != "mosh" || url.host_str() != Some("group") {
            return Err(PrivateGroupError::InvalidInvite("wrong scheme".to_string()));
        }
        let mesh = query(&url, "mesh")?;
        let group = query(&url, "group")?;
        let fingerprint = url.fragment().unwrap_or_default().replace("fp=", "");
        if fingerprint.is_empty() {
            return Err(PrivateGroupError::InvalidInvite(
                "missing creator fingerprint".to_string(),
            ));
        }
        if fingerprint.len() != INVITE_FINGERPRINT_LEN
            || !fingerprint.chars().all(|c| c.is_ascii_hexdigit())
        {
            return Err(PrivateGroupError::InvalidInvite(
                "fingerprint must be 32 hex chars".to_string(),
            ));
        }
        let fingerprint = fingerprint.to_ascii_uppercase();
        let label = optional_query(&url, "name");
        Ok(Self {
            mesh_id: mesh,
            group_id: group,
            creator_fingerprint: fingerprint,
            label: label.and_then(sanitize_label_str),
        })
    }
}

pub(super) fn build_invite_uri(
    mesh_id: &str,
    group_id: &str,
    fingerprint: &str,
    label: &Option<String>,
) -> String {
    match label.as_ref().and_then(|value| {
        let encoded = url::form_urlencoded::byte_serialize(value.as_bytes()).collect::<String>();
        if encoded.is_empty() {
            None
        } else {
            Some(encoded)
        }
    }) {
        Some(encoded) => format!(
            "{INVITE_PREFIX}?mesh={mesh_id}&group={group_id}&name={encoded}#fp={fingerprint}"
        ),
        None => format!("{INVITE_PREFIX}?mesh={mesh_id}&group={group_id}#fp={fingerprint}"),
    }
}

pub(super) fn sanitize_label(raw: Option<String>) -> Result<Option<String>, PrivateGroupError> {
    Ok(raw.and_then(sanitize_label_str))
}

pub(super) fn sanitize_label_str(raw: String) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    let truncated: String = trimmed.chars().take(MAX_LABEL_LEN).collect();
    Some(truncated)
}

pub(super) fn query(url: &url::Url, key: &str) -> Result<String, PrivateGroupError> {
    optional_query(url, key)
        .ok_or_else(|| PrivateGroupError::InvalidInvite(format!("missing {key}")))
}

pub(super) fn optional_query(url: &url::Url, key: &str) -> Option<String> {
    url.query_pairs()
        .find(|(candidate, _)| candidate == key)
        .map(|(_, value)| value.into_owned())
        .filter(|value| !value.is_empty())
}
