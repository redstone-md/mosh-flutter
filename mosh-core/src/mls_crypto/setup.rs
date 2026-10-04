use super::*;

impl MlsSessionCrypto {
    pub fn new(identity: &str) -> Result<Self, MlsCryptoError> {
        let provider = PersistentProvider::default();
        let signer =
            SignatureKeyPair::new(SignatureScheme::ED25519).map_err(MlsCryptoError::openmls)?;
        signer
            .store(provider.storage())
            .map_err(MlsCryptoError::openmls)?;
        let credential = BasicCredential::new(identity.as_bytes().to_vec());
        let credential = CredentialWithKey {
            credential: credential.into(),
            signature_key: signer.to_public_vec().into(),
        };
        Ok(Self {
            provider,
            signer,
            credential,
            group: None,
        })
    }

    pub fn create_group(&mut self) -> Result<(), MlsCryptoError> {
        let config = MlsGroupCreateConfig::builder()
            .ciphersuite(CIPHERSUITE)
            .use_ratchet_tree_extension(true)
            .build();
        let group = MlsGroup::new(
            &self.provider,
            &self.signer,
            &config,
            self.credential.clone(),
        )
        .map_err(MlsCryptoError::openmls)?;
        self.group = Some(group);
        Ok(())
    }

    pub fn key_package_bytes(&mut self) -> Result<Vec<u8>, MlsCryptoError> {
        self.serialize_key_package(KeyPackage::builder())
    }

    #[cfg(test)]
    pub(crate) fn key_package_with_lifetime(
        &mut self,
        lifetime: Lifetime,
    ) -> Result<Vec<u8>, MlsCryptoError> {
        self.serialize_key_package(KeyPackage::builder().key_package_lifetime(lifetime))
    }

    fn serialize_key_package(&self, builder: KeyPackageBuilder) -> Result<Vec<u8>, MlsCryptoError> {
        let key_package = builder
            .build(
                CIPHERSUITE,
                &self.provider,
                &self.signer,
                self.credential.clone(),
            )
            .map_err(MlsCryptoError::openmls)?;
        MlsMessageOut::from(key_package)
            .to_bytes()
            .map_err(MlsCryptoError::codec)
    }

    pub fn join_welcome(
        &mut self,
        welcome_bytes: &[u8],
        tree_bytes: &[u8],
    ) -> Result<(), MlsCryptoError> {
        let group = Self::stage_welcome(&self.provider, welcome_bytes, tree_bytes)?
            .into_group(&self.provider)
            .map_err(MlsCryptoError::openmls)?;
        self.group = Some(group);
        Ok(())
    }

    /// Stage against a copy: OpenMLS consumes the KeyPackage before exposing
    /// the verified author, even when the caller rejects that author.
    pub(crate) fn join_welcome_pinned(
        &mut self,
        welcome_bytes: &[u8],
        tree_bytes: &[u8],
        fingerprint: &str,
        full_signer: Option<&[u8]>,
        expected_identity: Option<&str>,
    ) -> Result<String, MlsCryptoError> {
        let provider =
            PersistentProvider::from_snapshot(&self.snapshot()).map_err(MlsCryptoError::codec)?;
        let staged = Self::stage_welcome(&provider, welcome_bytes, tree_bytes)?;
        let author = staged.welcome_sender().map_err(MlsCryptoError::openmls)?;
        let signer = author.signature_key().as_slice();
        if fingerprint_from_signature_key(signer) != fingerprint
            || full_signer.is_some_and(|expected| expected != signer)
        {
            return Err(MlsCryptoError::OpenMls(
                "Welcome author differs from invitation owner".into(),
            ));
        }
        let name = Self::credential_identity(author.credential()).ok_or_else(|| {
            MlsCryptoError::OpenMls("Welcome author requires a basic credential".into())
        })?;
        if expected_identity.is_some_and(|expected| expected != name) {
            return Err(MlsCryptoError::OpenMls(
                "Welcome credential differs from authorized sender".into(),
            ));
        }
        let group = staged
            .into_group(&provider)
            .map_err(MlsCryptoError::openmls)?;
        self.provider = provider;
        self.group = Some(group);
        Ok(name)
    }

    fn stage_welcome(
        provider: &PersistentProvider,
        welcome_bytes: &[u8],
        tree_bytes: &[u8],
    ) -> Result<StagedWelcome, MlsCryptoError> {
        let welcome_message = MlsMessageIn::tls_deserialize(&mut &welcome_bytes[..])
            .map_err(MlsCryptoError::codec)?;
        let welcome = match welcome_message.extract() {
            MlsMessageBodyIn::Welcome(welcome) => welcome,
            _ => return Err(MlsCryptoError::Codec("expected Welcome".to_string())),
        };
        let tree =
            RatchetTreeIn::tls_deserialize(&mut &tree_bytes[..]).map_err(MlsCryptoError::codec)?;
        StagedWelcome::new_from_welcome(
            provider,
            &MlsGroupJoinConfig::default(),
            welcome,
            Some(tree),
        )
        .map_err(MlsCryptoError::openmls)
    }

    pub(super) fn decode_key_package(&self, bytes: &[u8]) -> Result<KeyPackage, MlsCryptoError> {
        decode_key_package_impl(&self.provider, bytes)
    }
}
