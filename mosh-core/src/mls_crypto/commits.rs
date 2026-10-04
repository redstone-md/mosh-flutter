use super::*;

impl MlsSessionCrypto {
    /// 2-PARTY ONLY. Adds a peer and returns just `(welcome, tree)`, discarding
    /// the commit. That is safe only because the single new member joins via the
    /// welcome and there are no *other* existing members who would need the
    /// commit to advance their epoch. For a group of 3+, use `add_members` and
    /// broadcast `commit_bytes` to existing members, or they desync.
    pub fn add_peer(
        &mut self,
        key_package_bytes: &[u8],
    ) -> Result<(Vec<u8>, Vec<u8>), MlsCryptoError> {
        let outcome = self.add_members(&[key_package_bytes])?;
        Ok((outcome.welcome_bytes, outcome.tree_bytes))
    }

    pub fn add_members(
        &mut self,
        key_packages_bytes: &[&[u8]],
    ) -> Result<AddOutcome, MlsCryptoError> {
        let key_packages: Vec<KeyPackage> = key_packages_bytes
            .iter()
            .map(|raw| self.decode_key_package(raw))
            .collect::<Result<_, _>>()?;
        let group = self.group.as_mut().ok_or(MlsCryptoError::NotReady)?;
        let (commit, welcome, _group_info) = group
            .add_members(&self.provider, &self.signer, &key_packages)
            .map_err(MlsCryptoError::openmls)?;
        group
            .merge_pending_commit(&self.provider)
            .map_err(MlsCryptoError::openmls)?;
        Ok(AddOutcome {
            commit_bytes: commit.to_bytes().map_err(MlsCryptoError::codec)?,
            welcome_bytes: welcome.to_bytes().map_err(MlsCryptoError::codec)?,
            tree_bytes: group
                .export_ratchet_tree()
                .tls_serialize_detached()
                .map_err(MlsCryptoError::codec)?,
        })
    }

    pub fn process_commit(&mut self, commit_bytes: &[u8]) -> Result<(), MlsCryptoError> {
        self.process_commit_authenticated(commit_bytes, None)
    }

    pub(super) fn process_commit_authenticated(
        &mut self,
        commit_bytes: &[u8],
        expected: Option<&str>,
    ) -> Result<(), MlsCryptoError> {
        let group = self.group.as_mut().ok_or(MlsCryptoError::NotReady)?;
        let message =
            MlsMessageIn::tls_deserialize(&mut &commit_bytes[..]).map_err(MlsCryptoError::codec)?;
        let protocol_message = message
            .try_into_protocol_message()
            .map_err(MlsCryptoError::codec)?;
        let processed = group
            .process_message(&self.provider, protocol_message)
            .map_err(MlsCryptoError::openmls)?;
        if let Some(expected) = expected {
            let signer = match processed.sender() {
                Sender::Member(index) => group
                    .members()
                    .find(|member| member.index == *index)
                    .map(|member| hex::encode(member.signature_key)),
                _ => None,
            };
            if signer.as_deref() != Some(expected) {
                return Err(MlsCryptoError::NotReady);
            }
        }
        match processed.into_content() {
            ProcessedMessageContent::StagedCommitMessage(staged) => {
                group
                    .merge_staged_commit(&self.provider, *staged)
                    .map_err(MlsCryptoError::openmls)?;
                Ok(())
            }
            _ => Err(MlsCryptoError::OpenMls(
                "expected staged commit".to_string(),
            )),
        }
    }

    pub fn leave_proposal_bytes(&mut self) -> Result<Vec<u8>, MlsCryptoError> {
        let group = self.group.as_mut().ok_or(MlsCryptoError::NotReady)?;
        let proposal = group
            .leave_group(&self.provider, &self.signer)
            .map_err(MlsCryptoError::openmls)?;
        proposal.to_bytes().map_err(MlsCryptoError::codec)
    }

    /// Commit a member's departure, given the self-removal proposal it
    /// broadcast. The proposal is only used as proof: it must be a Remove
    /// naming the very leaf that signed it, so this can never be turned into
    /// "have someone else kicked". The removal is then re-issued as our own,
    /// inline, so the commit stands on its own — a member that never saw the
    /// proposal can still process it, which `commit_to_pending_proposals`
    /// (`ProposalRef`-style) would not allow.
    pub fn commit_departure(&mut self, proposal_bytes: &[u8]) -> Result<Vec<u8>, MlsCryptoError> {
        let leaving = self.staged_self_removal(proposal_bytes)?;
        self.remove_leaves(&[leaving])
    }

    /// Validate a self-removal proposal and return the leaf it retires.
    fn staged_self_removal(
        &mut self,
        proposal_bytes: &[u8],
    ) -> Result<LeafNodeIndex, MlsCryptoError> {
        let group = self.group.as_mut().ok_or(MlsCryptoError::NotReady)?;
        let protocol_message = decode_protocol_message(proposal_bytes)?;
        let processed = group
            .process_message(&self.provider, protocol_message)
            .map_err(MlsCryptoError::openmls)?;
        let sender = processed.sender().clone();
        let ProcessedMessageContent::ProposalMessage(queued) = processed.into_content() else {
            return Err(MlsCryptoError::OpenMls(
                "expected proposal message".to_string(),
            ));
        };
        let Proposal::Remove(remove) = queued.proposal() else {
            return Err(MlsCryptoError::OpenMls(
                "expected a remove proposal".to_string(),
            ));
        };
        let removed = remove.removed();
        match sender {
            Sender::Member(author) if author == removed => Ok(removed),
            _ => Err(MlsCryptoError::OpenMls(
                "remove proposal is not a self-removal".to_string(),
            )),
        }
    }
}
