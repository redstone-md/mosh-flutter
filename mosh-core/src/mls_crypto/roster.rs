use super::*;

impl MlsSessionCrypto {
    pub fn key_package_signer_is_member(
        &self,
        key_package_bytes: &[u8],
    ) -> Result<bool, MlsCryptoError> {
        let key_package = decode_key_package_impl(&self.provider, key_package_bytes)?;
        let candidate = key_package.leaf_node().signature_key().as_slice();
        let Some(group) = self.group.as_ref() else {
            return Ok(false);
        };
        Ok(group
            .members()
            .any(|member| member.signature_key.as_slice() == candidate))
    }

    pub fn member_count(&self) -> usize {
        match &self.group {
            Some(group) => group.members().count(),
            None => 0,
        }
    }

    pub(super) fn credential_identity(credential: &Credential) -> Option<String> {
        BasicCredential::try_from(credential.clone())
            .ok()
            .map(|basic| String::from_utf8_lossy(basic.identity()).into_owned())
    }

    /// Leaf credential identities. In org contexts the identity is the moss
    /// peer-id (ADR 0004), making leaf -> member lookup direct.
    pub fn member_identities(&self) -> Vec<String> {
        let Some(group) = self.group.as_ref() else {
            return Vec::new();
        };
        group
            .members()
            .filter_map(|member| Self::credential_identity(&member.credential))
            .collect()
    }

    // Excludes the own leaf: org kick/replace operate on OTHER members by
    // protocol (self-removal goes through leave_proposal_bytes, which another
    // member commits). Guards against a client acting on a roster diff
    // that names itself.
    fn leaf_indices_matching(group: &MlsGroup, identity: &str) -> Vec<LeafNodeIndex> {
        let own = group.own_leaf_index();
        group
            .members()
            .filter(|member| {
                member.index != own
                    && Self::credential_identity(&member.credential).as_deref() == Some(identity)
            })
            .map(|member| member.index)
            .collect()
    }

    /// Remove EVERY leaf whose credential identity matches, in one commit
    /// (duplicates are legal: a rejoin can leave a stale leaf, ADR 0004).
    /// Returns the commit for broadcast to remaining members.
    pub fn remove_members_by_identity(
        &mut self,
        identity: &str,
    ) -> Result<Vec<u8>, MlsCryptoError> {
        let group = self.group.as_ref().ok_or(MlsCryptoError::NotReady)?;
        let targets = Self::leaf_indices_matching(group, identity);
        if targets.is_empty() {
            return Err(MlsCryptoError::OpenMls(format!(
                "no member with identity {identity}"
            )));
        }
        self.remove_leaves(&targets)
    }

    /// Remove leaves in one commit and merge it locally. The Remove proposals
    /// ride inline, so the commit is self-contained for every receiver.
    pub(super) fn remove_leaves(
        &mut self,
        targets: &[LeafNodeIndex],
    ) -> Result<Vec<u8>, MlsCryptoError> {
        let group = self.group.as_mut().ok_or(MlsCryptoError::NotReady)?;
        let (commit, _welcome, _info) = group
            .remove_members(&self.provider, &self.signer, targets)
            .map_err(MlsCryptoError::openmls)?;
        // Serialize BEFORE merging: if to_bytes failed after the merge, the
        // local epoch would already be advanced while the commit is never
        // broadcast — a silent permanent fork.
        let commit_bytes = commit.to_bytes().map_err(MlsCryptoError::codec);
        if commit_bytes.is_err() {
            let _ = group.clear_pending_commit(self.provider.storage());
            return commit_bytes;
        }
        group
            .merge_pending_commit(&self.provider)
            .map_err(MlsCryptoError::openmls)?;
        commit_bytes
    }

    /// Remove every leaf matching `identity` and add the replacement
    /// KeyPackage in a single commit (spec §8 device replace; ADR 0004
    /// add-time dedup). With no matching leaf this is a plain Add.
    pub fn replace_member(
        &mut self,
        identity: &str,
        key_package_bytes: &[u8],
    ) -> Result<AddOutcome, MlsCryptoError> {
        let key_package = self.decode_key_package(key_package_bytes)?;
        let group = self.group.as_mut().ok_or(MlsCryptoError::NotReady)?;
        // CommitBuilder carries the Remove+Add proposals INLINE (by value) in
        // the commit, so receivers need no separate proposal messages —
        // commit_to_pending_proposals would reference proposals they never saw.
        let targets = Self::leaf_indices_matching(group, identity);
        let bundle = group
            .commit_builder()
            .propose_removals(targets)
            .propose_adds([key_package])
            .load_psks(self.provider.storage())
            .map_err(MlsCryptoError::openmls)?
            .build(
                self.provider.rand(),
                self.provider.crypto(),
                &self.signer,
                |_| true,
            )
            .map_err(MlsCryptoError::openmls)?
            .stage_commit(&self.provider)
            .map_err(MlsCryptoError::openmls)?;
        self.merge_replacement(bundle)
    }

    // Serialize before merging; discard staged state if serialization fails.
    fn merge_replacement(
        &mut self,
        bundle: CommitMessageBundle,
    ) -> Result<AddOutcome, MlsCryptoError> {
        let group = self.group.as_mut().ok_or(MlsCryptoError::NotReady)?;
        let serialized: Result<AddOutcome, MlsCryptoError> = (|| {
            let commit_bytes = bundle.commit().to_bytes().map_err(MlsCryptoError::codec)?;
            let welcome_bytes = bundle
                .to_welcome_msg()
                .ok_or_else(|| {
                    MlsCryptoError::OpenMls("commit with Add produced no welcome".to_string())
                })?
                .to_bytes()
                .map_err(MlsCryptoError::codec)?;
            let tree_bytes = group
                .pending_commit()
                .ok_or(MlsCryptoError::NotReady)?
                .export_ratchet_tree(self.provider.crypto(), group.export_ratchet_tree())
                .map_err(MlsCryptoError::openmls)?
                .ok_or(MlsCryptoError::NotReady)?
                .tls_serialize_detached()
                .map_err(MlsCryptoError::codec)?;
            Ok(AddOutcome {
                commit_bytes,
                welcome_bytes,
                tree_bytes,
            })
        })();
        // On serialization failure drop the staged commit, or every later
        // commit-producing call on this group fails on the stale pending state.
        let outcome = match serialized {
            Ok(outcome) => outcome,
            Err(error) => {
                let _ = group.clear_pending_commit(self.provider.storage());
                return Err(error);
            }
        };
        group
            .merge_pending_commit(&self.provider)
            .map_err(MlsCryptoError::openmls)?;
        Ok(outcome)
    }

    /// Credential identity inside a serialized KeyPackage. The admission
    /// rule (ADR 0004) compares it against the envelope's verified peer-id
    /// before the admin admits the leaf.
    pub fn key_package_identity(&self, key_package_bytes: &[u8]) -> Result<String, MlsCryptoError> {
        let key_package = self.decode_key_package(key_package_bytes)?;
        Self::credential_identity(key_package.leaf_node().credential()).ok_or_else(|| {
            MlsCryptoError::OpenMls("key package credential is not basic".to_string())
        })
    }

    pub fn member_fingerprints(&self) -> Vec<String> {
        let Some(group) = self.group.as_ref() else {
            return Vec::new();
        };
        group
            .members()
            .map(|member| fingerprint_from_signature_key(&member.signature_key))
            .collect()
    }

    pub(crate) fn member_signers(&self) -> Vec<String> {
        self.group
            .as_ref()
            .map(|group| {
                group
                    .members()
                    .map(|member| hex::encode(member.signature_key))
                    .collect()
            })
            .unwrap_or_default()
    }

    pub(crate) fn key_package_signer(&self, bytes: &[u8]) -> Result<String, MlsCryptoError> {
        Ok(hex::encode(
            self.decode_key_package(bytes)?
                .leaf_node()
                .signature_key()
                .as_slice(),
        ))
    }
}
