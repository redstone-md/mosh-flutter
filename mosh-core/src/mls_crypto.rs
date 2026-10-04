use openmls::prelude::tls_codec::{Deserialize, Serialize};
use openmls::prelude::*;
use openmls_basic_credential::SignatureKeyPair;
use openmls_traits::types::SignatureScheme;

use crate::mls_storage::PersistentProvider;

mod commits;
mod membership;
mod messages;
mod metadata;
mod roster;
mod setup;
mod storage;

const CIPHERSUITE: Ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;
const FINGERPRINT_LEN: usize = 16;

#[derive(Debug)]
pub enum MlsCryptoError {
    OpenMls(String),
    Codec(String),
    NotReady,
}

impl std::fmt::Display for MlsCryptoError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::OpenMls(error) => write!(formatter, "OpenMLS error: {error}"),
            Self::Codec(error) => write!(formatter, "codec error: {error}"),
            Self::NotReady => write!(formatter, "MLS group not initialized"),
        }
    }
}

impl std::error::Error for MlsCryptoError {}

impl MlsCryptoError {
    fn openmls(error: impl std::fmt::Display) -> Self {
        Self::OpenMls(error.to_string())
    }
    fn codec(error: impl std::fmt::Display) -> Self {
        Self::Codec(error.to_string())
    }
}

pub struct AddOutcome {
    pub commit_bytes: Vec<u8>,
    pub welcome_bytes: Vec<u8>,
    pub tree_bytes: Vec<u8>,
}

pub struct MlsSessionCrypto {
    provider: PersistentProvider,
    signer: SignatureKeyPair,
    credential: CredentialWithKey,
    group: Option<MlsGroup>,
}

fn fingerprint_from_signature_key(bytes: &[u8]) -> String {
    hex::encode_upper(&bytes[..bytes.len().min(FINGERPRINT_LEN)])
}

fn decode_key_package_impl(
    provider: &PersistentProvider,
    bytes: &[u8],
) -> Result<KeyPackage, MlsCryptoError> {
    let message = MlsMessageIn::tls_deserialize(&mut &bytes[..]).map_err(MlsCryptoError::codec)?;
    let key_package = match message.extract() {
        MlsMessageBodyIn::KeyPackage(key_package) => key_package,
        _ => return Err(MlsCryptoError::Codec("expected KeyPackage".to_string())),
    };
    let key_package = key_package
        .validate(provider.crypto(), ProtocolVersion::default())
        .map_err(MlsCryptoError::openmls)?;
    if !key_package.life_time().has_acceptable_range() {
        return Err(MlsCryptoError::OpenMls(
            "key package lifetime exceeds the accepted range".into(),
        ));
    }
    Ok(key_package)
}

#[cfg(test)]
mod tests;

fn decode_protocol_message(bytes: &[u8]) -> Result<ProtocolMessage, MlsCryptoError> {
    MlsMessageIn::tls_deserialize(&mut &bytes[..])
        .map_err(MlsCryptoError::codec)?
        .try_into_protocol_message()
        .map_err(MlsCryptoError::codec)
}
