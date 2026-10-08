//! Fixed-width invitation proof. General sender proofs keep their existing wire format.
use super::invite::ParsedInvite;
use crate::mls_crypto::MlsSessionCrypto;
use crate::org_envelope::{self, OrgContext, OrgSigned};
use crate::sender_auth::VerifiedSender;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use ed25519_dalek::{Signature, SigningKey, VerifyingKey};

pub(super) const PREFIX: &str = "mosh://invite/";
const HEADER_BYTES: usize = 82;
const SIGNATURE_BYTES: usize = 128;
const TARGET: u8 = 1;
const TOKEN: u8 = 2;

struct Decoded {
    invite: ParsedInvite,
    target: Option<String>,
    token: Option<String>,
    owner: VerifiedSender,
}

fn context(mesh: &str) -> OrgContext<'_> {
    OrgContext {
        org_pubkey: "",
        mesh_id: mesh,
        channel_kind: "dm-invite-owner-v2",
    }
}

/// Only canonical generated URLs are compacted. Extended or reordered legacy
/// URLs retain their complete signed transcript and their original parser.
pub(super) fn sign(
    raw: &str,
    identity: &SigningKey,
    crypto: &MlsSessionCrypto,
) -> Result<Option<String>, String> {
    let invite = ParsedInvite::parse(raw).map_err(|error| error.to_string())?;
    let target = super::invite_ownership::target_peer(raw)?;
    let token = super::invite_ownership::invitation_token(raw)?;
    if canonical(&invite, target.as_deref(), token.as_deref()) != raw {
        return Ok(None);
    }
    let Some(mesh) = token_bytes(&invite.mesh_id, "mesh-") else {
        return Ok(None);
    };
    let Some(session) = token_bytes(&invite.session_id, "session-") else {
        return Ok(None);
    };
    let owner = hex::encode(identity.verifying_key().to_bytes());
    if invite.peer_moss_id.as_deref() != Some(&owner) || invite.fingerprint != crypto.fingerprint()
    {
        return Err("invitation is not owned by the signing installation".into());
    }
    let mut bytes = vec![
        1,
        (u8::from(target.is_some()) * TARGET) | (u8::from(token.is_some()) * TOKEN),
    ];
    bytes.extend(mesh);
    bytes.extend(session);
    bytes.extend(identity.verifying_key().to_bytes());
    bytes.extend(crypto.signer_public());
    if let Some(token) = token {
        let Some(token) = token_bytes(&token, "invite-") else {
            return Ok(None);
        };
        bytes.extend(token);
    }
    if let Some(target) = target {
        bytes.extend(hex::decode(target).map_err(|error| error.to_string())?);
    }
    let input = org_envelope::signing_input(&context(&invite.mesh_id), &bytes);
    let mls_signature = crypto
        .sign_sender_proof(&input)
        .map_err(|error| error.to_string())?;
    let identity_signature = org_envelope::sign(identity, &context(&invite.mesh_id), &bytes).sig;
    bytes.extend(identity_signature);
    bytes.extend(mls_signature);
    Ok(Some(format!("{PREFIX}{}", URL_SAFE_NO_PAD.encode(bytes))))
}

pub(super) fn parse(raw: &str) -> Result<ParsedInvite, String> {
    Ok(decode(raw)?.invite)
}

pub(super) fn owner(raw: &str) -> Result<VerifiedSender, String> {
    Ok(decode(raw)?.owner)
}

pub(super) fn target(raw: &str) -> Result<Option<String>, String> {
    Ok(decode(raw)?.target)
}

pub(super) fn token(raw: &str) -> Result<Option<String>, String> {
    Ok(decode(raw)?.token)
}

fn decode(raw: &str) -> Result<Decoded, String> {
    let encoded = raw
        .strip_prefix(PREFIX)
        .ok_or("invalid compact invite prefix")?;
    let bytes = URL_SAFE_NO_PAD
        .decode(encoded)
        .map_err(|error| error.to_string())?;
    if URL_SAFE_NO_PAD.encode(&bytes) != encoded
        || bytes.len() < HEADER_BYTES + SIGNATURE_BYTES
        || bytes[0] != 1
        || bytes[1] & !(TARGET | TOKEN) != 0
    {
        return Err("invalid compact invitation".into());
    }
    let flags = bytes[1];
    let payload_len =
        HEADER_BYTES + usize::from(flags & TOKEN != 0) * 8 + usize::from(flags & TARGET != 0) * 32;
    if bytes.len() != payload_len + SIGNATURE_BYTES {
        return Err("invalid compact invitation length".into());
    }
    let invite = ParsedInvite {
        mesh_id: format!("mesh-{}", hex::encode(&bytes[2..10])),
        session_id: format!("session-{}", hex::encode(&bytes[10..18])),
        peer_address: None,
        peer_moss_id: Some(hex::encode(&bytes[18..50])),
        fingerprint: hex::encode_upper(&bytes[50..66]),
    };
    verify(&bytes, payload_len, &invite.mesh_id)?;
    let token = (flags & TOKEN != 0).then(|| format!("invite-{}", hex::encode(&bytes[82..90])));
    let target_start = HEADER_BYTES + usize::from(token.is_some()) * 8;
    let target =
        (flags & TARGET != 0).then(|| hex::encode(&bytes[target_start..target_start + 32]));
    let owner = VerifiedSender {
        peer_id: invite.peer_moss_id.clone().ok_or("missing owner")?,
        mls_signer: bytes[50..82].to_vec(),
        payload: canonical(&invite, target.as_deref(), token.as_deref()).into_bytes(),
    };
    Ok(Decoded {
        invite,
        target,
        token,
        owner,
    })
}

fn verify(bytes: &[u8], payload_len: usize, mesh: &str) -> Result<(), String> {
    let ctx = context(mesh);
    org_envelope::verify(
        &OrgSigned {
            payload: bytes[..payload_len].to_vec(),
            peer_id: hex::encode(&bytes[18..50]),
            sig: bytes[payload_len..payload_len + 64].to_vec(),
        },
        &ctx,
    )
    .map_err(|error| error.to_string())?;
    let key: [u8; 32] = bytes[50..82].try_into().map_err(|_| "invalid MLS owner")?;
    VerifyingKey::from_bytes(&key)
        .map_err(|error| error.to_string())?
        .verify_strict(
            &org_envelope::signing_input(&ctx, &bytes[..payload_len]),
            &Signature::from_slice(&bytes[payload_len + 64..])
                .map_err(|error| error.to_string())?,
        )
        .map_err(|error| error.to_string())
}

fn canonical(invite: &ParsedInvite, target: Option<&str>, token: Option<&str>) -> String {
    let raw = super::invite::build_invite_uri(
        &invite.mesh_id,
        &invite.session_id,
        &invite.fingerprint,
        invite.peer_moss_id.as_deref(),
    );
    let mut url = url::Url::parse(&raw).expect("generated invitation URL");
    if let Some(token) = token {
        url.query_pairs_mut().append_pair("token", token);
    }
    if let Some(target) = target {
        url.query_pairs_mut().append_pair("target", target);
    }
    url.into()
}

fn token_bytes(token: &str, prefix: &str) -> Option<[u8; 8]> {
    let hex = token.strip_prefix(prefix)?;
    if hex.len() != 16 || hex.bytes().any(|byte| byte.is_ascii_uppercase()) {
        return None;
    }
    hex::decode(hex).ok()?.try_into().ok()
}

#[cfg(test)]
#[path = "compact_invite_tests.rs"]
mod tests;
