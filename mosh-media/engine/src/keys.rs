//! Consuming X25519 agreement. Only public descriptions leave the native engine.
use hkdf::Hkdf;
use ringrtc::webrtc::sdp_observer::{SrtpCryptoSuite, SrtpKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use x25519_dalek::{EphemeralSecret, PublicKey};
use zeroize::{Zeroize, Zeroizing};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct MediaBinding {
    pub session_id: String,
    pub call_id: String,
    pub caller: String,
    pub callee: String,
    pub media_session: Vec<u8>,
}

impl MediaBinding {
    pub fn validate(&self) -> anyhow::Result<()> {
        for id in [&self.session_id, &self.call_id, &self.caller, &self.callee] {
            anyhow::ensure!(!id.is_empty() && id.len() <= 128, "invalid media binding");
        }
        anyhow::ensure!(
            self.caller != self.callee && self.media_session.len() == 16,
            "invalid selected media identities or session nonce"
        );
        Ok(())
    }

    fn encode(&self) -> Vec<u8> {
        let mut info = b"Mosh selected call media v1 AES-256-GCM SRTP".to_vec();
        for id in [&self.session_id, &self.call_id, &self.caller, &self.callee] {
            info.extend((id.len() as u32).to_be_bytes());
            info.extend(id.as_bytes());
        }
        info.extend(&self.media_session);
        info
    }
}

#[derive(Clone, Copy)]
pub enum Role {
    Caller,
    Callee,
}

pub struct Agreement {
    secret: EphemeralSecret,
    public: [u8; 32],
}

impl Default for Agreement {
    fn default() -> Self {
        Self::new()
    }
}

impl Agreement {
    pub fn new() -> Self {
        let secret = EphemeralSecret::random_from_rng(&mut rand::rng());
        let public = *PublicKey::from(&secret).as_bytes();
        Self { secret, public }
    }

    pub fn public_key(&self) -> [u8; 32] {
        self.public
    }

    pub fn finish(
        self,
        remote: &[u8],
        binding: &MediaBinding,
        role: Role,
    ) -> anyhow::Result<SrtpKeys> {
        binding.validate()?;
        let remote: [u8; 32] = remote
            .try_into()
            .map_err(|_| anyhow::anyhow!("invalid public key size"))?;
        let shared = self.secret.diffie_hellman(&PublicKey::from(remote));
        anyhow::ensure!(
            shared.was_contributory(),
            "noncontributory media public key"
        );
        let mut context = binding.encode();
        let (caller, callee) = match role {
            Role::Caller => (self.public, remote),
            Role::Callee => (remote, self.public),
        };
        context.extend(caller);
        context.extend(callee);
        let salt = Sha256::digest(&context);
        let hkdf = Hkdf::<Sha256>::new(Some(&salt), shared.as_bytes());
        let mut material = Zeroizing::new([0u8; 88]);
        hkdf.expand(&context, &mut *material)
            .map_err(|_| anyhow::anyhow!("media derivation failed"))?;
        Ok(SrtpKeys {
            offer: key(&material[..32], &material[32..44]),
            answer: key(&material[44..76], &material[76..]),
        })
    }
}

pub struct SrtpKeys {
    pub offer: SrtpKey,
    pub answer: SrtpKey,
}

impl Drop for SrtpKeys {
    fn drop(&mut self) {
        self.offer.key.zeroize();
        self.offer.salt.zeroize();
        self.answer.key.zeroize();
        self.answer.salt.zeroize();
    }
}

fn key(key: &[u8], salt: &[u8]) -> SrtpKey {
    SrtpKey {
        suite: SrtpCryptoSuite::AeadAes256Gcm,
        key: key.to_vec(),
        salt: salt.to_vec(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn binding() -> MediaBinding {
        MediaBinding {
            session_id: "dm".into(),
            call_id: "call".into(),
            caller: "caller-leaf".into(),
            callee: "selected-leaf".into(),
            media_session: vec![7; 16],
        }
    }

    #[test]
    fn selected_pair_derives_matching_fresh_directional_keys() {
        let (caller, callee) = (Agreement::new(), Agreement::new());
        let (caller_public, callee_public) = (caller.public_key(), callee.public_key());
        let left = caller
            .finish(&callee_public, &binding(), Role::Caller)
            .unwrap();
        let right = callee
            .finish(&caller_public, &binding(), Role::Callee)
            .unwrap();
        assert!(left.offer.key == right.offer.key && left.offer.salt == right.offer.salt);
        assert!(left.answer.key == right.answer.key && left.answer.salt == right.answer.salt);
        assert!(left.offer.key != left.answer.key);
        assert_eq!((left.offer.key.len(), left.offer.salt.len()), (32, 12));
    }

    #[test]
    fn binding_is_unambiguous_and_includes_the_selected_pair_and_epoch() {
        let baseline = binding().encode();
        for changed in [
            MediaBinding {
                session_id: "other".into(),
                ..binding()
            },
            MediaBinding {
                call_id: "next".into(),
                ..binding()
            },
            MediaBinding {
                caller: "sibling".into(),
                ..binding()
            },
            MediaBinding {
                callee: "not-selected".into(),
                ..binding()
            },
            MediaBinding {
                media_session: vec![8; 16],
                ..binding()
            },
        ] {
            assert_ne!(baseline, changed.encode());
        }
        assert_ne!(
            MediaBinding {
                session_id: "a".into(),
                call_id: "bc".into(),
                ..binding()
            }
            .encode(),
            MediaBinding {
                session_id: "ab".into(),
                call_id: "c".into(),
                ..binding()
            }
            .encode()
        );
    }

    #[test]
    fn wrong_selected_context_cannot_derive_the_receivers_keys() {
        let (caller, callee) = (Agreement::new(), Agreement::new());
        let (caller_public, callee_public) = (caller.public_key(), callee.public_key());
        let left = caller
            .finish(&callee_public, &binding(), Role::Caller)
            .unwrap();
        let wrong = MediaBinding {
            callee: "other-leaf".into(),
            ..binding()
        };
        let right = callee.finish(&caller_public, &wrong, Role::Callee).unwrap();
        assert!(left.offer.key != right.offer.key && left.answer.key != right.answer.key);
    }

    #[test]
    fn rejects_invalid_and_low_order_public_keys() {
        assert!(
            Agreement::new()
                .finish(&[0; 32], &binding(), Role::Caller)
                .is_err()
        );
        assert!(
            Agreement::new()
                .finish(&[1; 31], &binding(), Role::Caller)
                .is_err()
        );
        assert!(
            MediaBinding {
                caller: "selected-leaf".into(),
                ..binding()
            }
            .validate()
            .is_err()
        );
    }
}
