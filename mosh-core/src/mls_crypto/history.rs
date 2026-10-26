//! Public facts from the installation's own verified MLS state, never leaf secrets.
use super::*;
use sha2::{Digest, Sha256};

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub(crate) struct MlsHistoryContext {
    pub(crate) group_id: Vec<u8>,
    pub(crate) epoch: u64,
    pub(crate) hash: String,
}

pub(crate) struct StagedMembership {
    pub(crate) next: MlsSessionCrypto,
    pub(crate) prior: MlsHistoryContext,
    pub(crate) context: MlsHistoryContext,
    pub(crate) author: Vec<u8>,
    pub(crate) removed: bool,
}

pub(crate) struct StagedAdmission {
    pub(crate) next: MlsSessionCrypto,
    pub(crate) context: MlsHistoryContext,
    pub(crate) author: Vec<u8>,
    pub(crate) author_identity: String,
}

impl MlsHistoryContext {
    pub(super) fn from_context(context: &GroupContext) -> Result<Self, MlsCryptoError> {
        let bytes = context
            .tls_serialize_detached()
            .map_err(MlsCryptoError::codec)?;
        Ok(Self {
            group_id: context.group_id().as_slice().to_vec(),
            epoch: context.epoch().as_u64(),
            hash: hex::encode(Sha256::digest(bytes)),
        })
    }
}

impl MlsSessionCrypto {
    pub(crate) fn history_context(&self) -> Result<MlsHistoryContext, MlsCryptoError> {
        let group = self.group.as_ref().ok_or(MlsCryptoError::NotReady)?;
        if !group.is_active() {
            return Err(MlsCryptoError::NotReady);
        }
        // 0.8.1 exposes the production GroupContext through GroupInfo. Its
        // direct MlsGroup context accessor is test-only; no vendor fork needed.
        let info = group
            .export_group_info(self.provider.crypto(), &self.signer, false)
            .map_err(MlsCryptoError::openmls)?;
        let MlsMessageBodyOut::GroupInfo(info) = info.body() else {
            return Err(MlsCryptoError::NotReady);
        };
        MlsHistoryContext::from_context(info.group_context())
    }
}
