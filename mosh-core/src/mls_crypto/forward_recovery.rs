//! A bounded DM-only retry; ordinary receive windows and stored policy stay intact.
use super::*;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const MAX_FORWARD_RECOVERY: u32 = 65_536;
const RETRY_INTERVAL: Duration = Duration::from_secs(10);

/// Copies used for application validation share refused attempts too.
#[derive(Default)]
pub(super) struct ForwardRecovery(Mutex<Option<Instant>>);

impl ForwardRecovery {
    fn admit(&self, now: Instant) -> bool {
        let mut previous = self.0.lock().unwrap_or_else(|error| error.into_inner());
        if previous.is_some_and(|time| now.saturating_duration_since(time) < RETRY_INTERVAL) {
            return false;
        }
        *previous = Some(now);
        true
    }
}

impl MlsSessionCrypto {
    pub(crate) fn enable_dm_forward_recovery(&mut self) {
        self.forward_recovery
            .get_or_insert_with(|| Arc::new(ForwardRecovery::default()));
    }

    pub(super) fn recover_forward_gap(
        &mut self,
        ciphertext: &[u8],
        error: MlsCryptoError,
    ) -> Result<(Vec<u8>, Vec<u8>), MlsCryptoError> {
        let Some(budget) = &self.forward_recovery else {
            return Err(error);
        };
        let configuration = self
            .group
            .as_ref()
            .ok_or(MlsCryptoError::NotReady)?
            .configuration()
            .clone();
        if configuration
            .sender_ratchet_configuration()
            .maximum_forward_distance()
            >= MAX_FORWARD_RECOVERY
            || !budget.admit(Instant::now())
        {
            return Err(error);
        }
        let mut candidate = self.receive_candidate()?;
        candidate.forward_recovery = None;
        candidate.set_recovery_window(&configuration)?;
        let plaintext = candidate.decrypt_with_signer(ciphertext)?;
        candidate
            .group
            .as_mut()
            .ok_or(MlsCryptoError::NotReady)?
            .set_configuration(candidate.provider.storage(), &configuration)
            .map_err(MlsCryptoError::codec)?;
        candidate.forward_recovery = self.forward_recovery.clone();
        *self = candidate;
        Ok(plaintext)
    }

    fn set_recovery_window(
        &mut self,
        configuration: &MlsGroupJoinConfig,
    ) -> Result<(), MlsCryptoError> {
        // 0.8.1 has no field updater. Preserve every serialized setting, including
        // flags without getters, and change only the typed sender-ratchet policy.
        let mut updated = serde_json::to_value(configuration).map_err(MlsCryptoError::codec)?;
        let ratchet = updated
            .get_mut("sender_ratchet_configuration")
            .ok_or_else(|| MlsCryptoError::Codec("missing MLS ratchet configuration".into()))?;
        *ratchet = serde_json::to_value(SenderRatchetConfiguration::new(
            configuration
                .sender_ratchet_configuration()
                .out_of_order_tolerance(),
            MAX_FORWARD_RECOVERY,
        ))
        .map_err(MlsCryptoError::codec)?;
        let updated = serde_json::from_value(updated).map_err(MlsCryptoError::codec)?;
        self.group
            .as_mut()
            .ok_or(MlsCryptoError::NotReady)?
            .set_configuration(self.provider.storage(), &updated)
            .map_err(MlsCryptoError::codec)
    }
}

#[cfg(test)]
mod tests;
