use super::*;

impl MlsSessionCrypto {
    /// Serialize MLS state for at-rest persistence.
    pub fn snapshot(&self) -> Vec<u8> {
        self.provider.snapshot_bytes()
    }

    /// Public signature key bytes (needed to re-read the signer on restore).
    pub fn signer_public(&self) -> Vec<u8> {
        self.signer.to_public_vec()
    }

    /// Group id bytes (the key for `MlsGroup::load`).
    pub fn group_id_bytes(&self) -> Option<Vec<u8>> {
        self.group
            .as_ref()
            .map(|g| g.group_id().as_slice().to_vec())
    }

    /// Rebuild a session from a persisted snapshot.
    pub fn restore(
        identity: &str,
        signer_public: &[u8],
        snapshot: &[u8],
        group_id: &[u8],
    ) -> Result<Self, MlsCryptoError> {
        Self::restore_state(identity, signer_public, snapshot, Some(group_id))
    }

    pub(crate) fn restore_unjoined(
        identity: &str,
        signer_public: &[u8],
        snapshot: &[u8],
    ) -> Result<Self, MlsCryptoError> {
        Self::restore_state(identity, signer_public, snapshot, None)
    }

    fn restore_state(
        identity: &str,
        signer_public: &[u8],
        snapshot: &[u8],
        group_id: Option<&[u8]>,
    ) -> Result<Self, MlsCryptoError> {
        let provider =
            PersistentProvider::from_snapshot(snapshot).map_err(MlsCryptoError::codec)?;
        let signer =
            SignatureKeyPair::read(provider.storage(), signer_public, SignatureScheme::ED25519)
                .ok_or_else(|| MlsCryptoError::OpenMls("signer not found in snapshot".into()))?;
        let credential = CredentialWithKey {
            credential: BasicCredential::new(identity.as_bytes().to_vec()).into(),
            signature_key: signer.to_public_vec().into(),
        };
        let group = group_id
            .map(|id| {
                MlsGroup::load(provider.storage(), &GroupId::from_slice(id))
                    .map_err(MlsCryptoError::openmls)?
                    .ok_or(MlsCryptoError::NotReady)
            })
            .transpose()?;
        Ok(Self {
            provider,
            signer,
            credential,
            group,
        })
    }
}
