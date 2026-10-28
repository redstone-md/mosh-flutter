//! Public own-tree facts survive rejoin without exporting or retaining old ratchets.
use super::*;
use crate::mls_crypto::MlsHistoryContext;
use crate::persistence::history_admission::EvidenceWrite;
use sha2::{Digest, Sha256};

#[derive(Serialize, Deserialize)]
struct NativeContext {
    context: MlsHistoryContext,
    members: Vec<String>,
}

pub(super) fn context_write(
    group: &str,
    crypto: &MlsSessionCrypto,
) -> Result<EvidenceWrite, PrivateGroupError> {
    let context = NativeContext {
        context: crypto.history_context()?,
        members: crypto.member_signers(),
    };
    Ok(EvidenceWrite {
        key: context_key(group, &context.context),
        bytes: serde_json::to_vec(&context).map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
    })
}

impl GroupSession {
    pub(super) fn known_member_at(
        &self,
        at: &MlsHistoryContext,
        key: &str,
    ) -> Result<Option<bool>, PrivateGroupError> {
        let head = self.crypto.history_context()?;
        if at.group_id != head.group_id || at.epoch > head.epoch {
            return Ok(None);
        }
        if *at == head {
            return Ok(Some(
                self.crypto
                    .member_signers()
                    .iter()
                    .any(|member| member == key),
            ));
        }
        let store = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        if let Some(context) =
            store.group_history_evidence::<NativeContext>(&context_key(&self.group_id, at))?
        {
            if context.context != *at {
                return Err(PrivateGroupError::Codec("native context differs".into()));
            }
            return Ok(Some(context.members.iter().any(|member| member == key)));
        }
        let prefix = format!(
            "group/{}/transition/",
            hex::encode(Sha256::digest(self.group_id.as_bytes()))
        );
        if let Some(transition) = store
            .group_history_evidence::<super::transitions::NativeTransition>(&format!(
                "{prefix}{:020}",
                at.epoch
            ))?
        {
            if transition.prior == *at {
                return Ok(Some(
                    transition
                        .previous_member_keys
                        .iter()
                        .any(|member| member == key),
                ));
            }
        }
        if let Some(epoch) = at.epoch.checked_sub(1) {
            if let Some(transition) = store
                .group_history_evidence::<super::transitions::NativeTransition>(&format!(
                    "{prefix}{epoch:020}"
                ))?
            {
                if transition.next == *at {
                    return Ok(Some(
                        transition
                            .next_member_keys
                            .iter()
                            .any(|member| member == key),
                    ));
                }
            }
        }
        Ok(None)
    }
}

fn context_key(group: &str, context: &MlsHistoryContext) -> String {
    format!(
        "group/{}/local-context/{}",
        hex::encode(Sha256::digest(group.as_bytes())),
        context.hash
    )
}
