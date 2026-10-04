//! Export a domain-separated epoch key without advancing application ratchets.
use super::*;

impl MlsSessionCrypto {
    pub(crate) fn metadata_key(
        &self,
        label: &str,
        context: &[u8],
    ) -> Result<Vec<u8>, MlsCryptoError> {
        self.group
            .as_ref()
            .ok_or(MlsCryptoError::NotReady)?
            .export_secret(self.provider.crypto(), label, context, 32)
            .map_err(MlsCryptoError::openmls)
    }
}
