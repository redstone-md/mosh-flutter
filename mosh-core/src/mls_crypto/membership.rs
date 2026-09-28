use super::*;

impl MlsSessionCrypto {
    pub(crate) fn remove_member_by_signer(
        &mut self,
        signer: &str,
    ) -> Result<Vec<u8>, MlsCryptoError> {
        let group = self.group.as_ref().ok_or(MlsCryptoError::NotReady)?;
        let target = group
            .members()
            .find(|member| {
                hex::encode(&member.signature_key) == signer
                    && member.index != group.own_leaf_index()
            })
            .ok_or(MlsCryptoError::NotReady)?
            .index;
        self.remove_leaves(&[target])
    }

    pub(crate) fn process_commit_from(
        &mut self,
        commit: &[u8],
        signer: &str,
    ) -> Result<(), MlsCryptoError> {
        self.process_commit_authenticated(commit, Some(signer))
    }
}
