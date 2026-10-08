//! An offered invite proves the same installation owns its DM MLS key.
use super::invite::ParsedInvite;
use crate::mls_crypto::MlsSessionCrypto;
use crate::org_envelope::OrgContext;
use crate::sender_auth::{SenderProof, VerifiedSender};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use ed25519_dalek::SigningKey;

fn context(invite: &ParsedInvite) -> OrgContext<'_> {
    OrgContext {
        org_pubkey: "",
        mesh_id: &invite.mesh_id,
        channel_kind: "dm-invite-owner-v1",
    }
}

/// Remove only the proof field; all routing and fingerprint fields remain
/// covered. Reject duplicates instead of interpreting them differently.
fn split(raw: &str) -> Result<(url::Url, Option<String>), String> {
    let mut url = url::Url::parse(raw).map_err(|error| error.to_string())?;
    let mut proof = None;
    let mut pairs = Vec::new();
    for (key, value) in url.query_pairs() {
        if key == "proof" {
            if proof.replace(value.into_owned()).is_some() {
                return Err("duplicate invite proof".into());
            }
        } else {
            pairs.push((key.into_owned(), value.into_owned()));
        }
    }
    url.set_query(None);
    url.query_pairs_mut().extend_pairs(pairs);
    Ok((url, proof))
}

pub(crate) fn sign_invite(
    raw: &str,
    identity: &SigningKey,
    crypto: &MlsSessionCrypto,
) -> Result<String, String> {
    let (mut unsigned, _) = split(raw)?;
    if let Some(compact) = super::compact_invite::sign(unsigned.as_str(), identity, crypto)? {
        return Ok(compact);
    }
    let invite = ParsedInvite::parse(unsigned.as_str()).map_err(|error| error.to_string())?;
    let peer_id = hex::encode(identity.verifying_key().to_bytes());
    if invite.peer_moss_id.as_deref() != Some(&peer_id)
        || invite.fingerprint != crypto.fingerprint()
    {
        return Err("invitation is not owned by the signing installation".into());
    }
    let proof = SenderProof::sign(
        identity,
        crypto,
        &context(&invite),
        unsigned.as_str().as_bytes().to_vec(),
    )?;
    let encoded =
        URL_SAFE_NO_PAD.encode(serde_json::to_vec(&proof).map_err(|error| error.to_string())?);
    unsigned.query_pairs_mut().append_pair("proof", &encoded);
    Ok(unsigned.into())
}

pub(super) fn verify_invite_owner(
    raw: &str,
    invite: &ParsedInvite,
) -> Result<Option<VerifiedSender>, String> {
    if raw.starts_with(super::compact_invite::PREFIX) && !raw.starts_with("mosh://invite/?") {
        return super::compact_invite::owner(raw).map(Some);
    }
    let (unsigned, proof) = split(raw)?;
    let Some(proof) = proof else {
        return Ok(None);
    };
    let proof: SenderProof = serde_json::from_slice(
        &URL_SAFE_NO_PAD
            .decode(proof)
            .map_err(|error| error.to_string())?,
    )
    .map_err(|error| error.to_string())?;
    let owner = proof.verify(&context(invite))?;
    if owner.payload != unsigned.as_str().as_bytes()
        || invite.peer_moss_id.as_deref() != Some(&owner.peer_id)
        || hex::encode_upper(&owner.mls_signer[..16]) != invite.fingerprint
    {
        return Err("invite ownership proof does not match the invitation".into());
    }
    Ok(Some(owner))
}

pub(crate) fn target_peer(raw: &str) -> Result<Option<String>, String> {
    if raw.starts_with(super::compact_invite::PREFIX) && !raw.starts_with("mosh://invite/?") {
        return super::compact_invite::target(raw);
    }
    let url = url::Url::parse(raw).map_err(|error| error.to_string())?;
    let targets: Vec<_> = url
        .query_pairs()
        .filter(|(key, _)| key == "target")
        .map(|(_, value)| value.into_owned())
        .collect();
    match targets.as_slice() {
        [] => Ok(None),
        [target] if target.len() == 64 && target.bytes().all(|byte| byte.is_ascii_hexdigit()) => {
            Ok(Some(target.to_lowercase()))
        }
        _ => Err("invitation requires one valid target identity".into()),
    }
}

pub(super) fn invitation_token(raw: &str) -> Result<Option<String>, String> {
    if raw.starts_with(super::compact_invite::PREFIX) && !raw.starts_with("mosh://invite/?") {
        return super::compact_invite::token(raw);
    }
    let url = url::Url::parse(raw).map_err(|error| error.to_string())?;
    let tokens: Vec<_> = url
        .query_pairs()
        .filter(|(key, _)| key == "token")
        .map(|(_, value)| value.into_owned())
        .collect();
    match tokens.as_slice() {
        [] => Ok(None),
        [token]
            if token.strip_prefix("invite-").is_some_and(|hex| {
                hex.len() == 16 && hex.bytes().all(|byte| byte.is_ascii_hexdigit())
            }) =>
        {
            Ok(Some(token.clone()))
        }
        _ => Err("invitation requires one valid admission token".into()),
    }
}

pub(crate) fn verify_offered_invite(
    raw: &str,
    expected_peer: &str,
    expected_target: &str,
) -> Result<(), String> {
    let invite = ParsedInvite::parse(raw).map_err(|error| error.to_string())?;
    let owner = verify_invite_owner(raw, &invite)?
        .ok_or("offered invitation requires an ownership proof")?;
    if owner.peer_id != expected_peer || target_peer(raw)?.as_deref() != Some(expected_target) {
        return Err("DM owner differs from the offering member".into());
    }
    Ok(())
}

#[cfg(test)]
#[path = "invite_ownership_tests.rs"]
mod tests;
