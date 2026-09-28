use super::super::admission::{stage_admission, verify_authorizer, verify_request};
use super::super::proof::verify;
use super::super::types::{Admission, JoinRequest};
use super::*;
use crate::device_link::identity::DeviceIdentity;
use crate::private_dm_runtime::now_ms;
use ed25519_dalek::Signer;
use serde::{Deserialize, Serialize};

/// Public commit evidence, signed by its original author and retained without
/// Welcome secrets or another installation's MLS snapshot.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime::devices) struct EpochAuthorization {
    pub roster: DeviceRoster,
    pub signature: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub admitted_at_ms: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime::devices) struct EpochRecord {
    pub author_device_id: String,
    pub roster: DeviceRoster,
    pub request: JoinRequest,
    pub commit: Vec<u8>,
    pub group_id: Vec<u8>,
    pub epoch: u64,
    pub signature: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub admitted_at_ms: Option<u64>,
}

impl EpochRecord {
    pub fn create(
        identity: &DeviceIdentity,
        admission: &Admission,
        admitted_at_ms: u64,
    ) -> Result<Self> {
        let mut record = Self::unsigned(identity.device(), identity.roster(), admission);
        record.admitted_at_ms = Some(admitted_at_ms);
        record.signature = hex::encode(identity.key().sign(&record.bytes()?).to_bytes());
        Ok(record)
    }

    pub fn from_admission(
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        admission: &Admission,
    ) -> Result<Option<Self>> {
        let Some(authorization) = &admission.recovery_authorization else {
            return Ok(None);
        };
        if !roster
            .extends(&authorization.roster)
            .map_err(|_| invalid())?
        {
            return Err(invalid());
        }
        let mut record = Self::unsigned(sender, &authorization.roster, admission);
        record.admitted_at_ms = authorization.admitted_at_ms;
        record.signature = authorization.signature.clone();
        if record.author()? != *sender {
            return Err(invalid());
        }
        Ok(Some(record))
    }

    pub fn authorization(&self) -> EpochAuthorization {
        EpochAuthorization {
            roster: self.roster.clone(),
            signature: self.signature.clone(),
            admitted_at_ms: self.admitted_at_ms,
        }
    }

    fn unsigned(sender: &DeviceDescriptor, roster: &DeviceRoster, admission: &Admission) -> Self {
        Self {
            author_device_id: sender.device_id.clone(),
            roster: roster.clone(),
            request: admission.request.clone(),
            commit: admission.commit.clone(),
            group_id: admission.group_id.clone(),
            epoch: admission.epoch,
            signature: String::new(),
            admitted_at_ms: None,
        }
    }

    fn bytes(&self) -> Result<Vec<u8>> {
        let mut bytes = match self.admitted_at_ms {
            Some(time) => {
                let mut bytes = b"mosh-dm-epoch-evidence-v2".to_vec();
                bytes.extend(time.to_be_bytes());
                bytes
            }
            None => b"mosh-dm-epoch-evidence-v1".to_vec(),
        };
        bytes.extend(
            serde_json::to_vec(&(
                &self.author_device_id,
                &self.roster,
                &self.request,
                &self.commit,
                &self.group_id,
                self.epoch,
            ))
            .map_err(|_| invalid())?,
        );
        Ok(bytes)
    }

    fn author(&self) -> Result<DeviceDescriptor> {
        let author = self
            .roster
            .devices()
            .map_err(|_| invalid())?
            .into_iter()
            .find(|device| device.device_id == self.author_device_id)
            .ok_or_else(invalid)?;
        verify(&author.signing_public_key, &self.signature, &self.bytes()?)?;
        Ok(author)
    }

    fn validation_time(&self) -> Result<Option<u64>> {
        if let Some(time) = self.admitted_at_ms {
            // Match OpenMLS's one-hour allowance for installation clock skew.
            if time == 0 || time > now_ms().saturating_add(3_600_000) {
                return Err(invalid());
            }
        }
        Ok(self.admitted_at_ms.map(|time| time / 1000))
    }

    fn admission(&self, membership: &DeviceMembership) -> Admission {
        Admission {
            request: self.request.clone(),
            commit: self.commit.clone(),
            welcome: Vec::new(),
            tree: Vec::new(),
            topology: membership.topology.clone(),
            group_id: self.group_id.clone(),
            epoch: self.epoch,
            recovery_authorization: Some(self.authorization()),
        }
    }
}

impl DeviceMembership {
    pub(in crate::private_dm_runtime::devices) fn retain_epoch(
        &mut self,
        record: EpochRecord,
    ) -> Result<()> {
        if let Some(existing) = self
            .epoch_records
            .iter()
            .find(|existing| existing.epoch == record.epoch)
        {
            if existing.commit != record.commit
                || existing.group_id != record.group_id
                || existing.author_device_id != record.author_device_id
            {
                return Err(invalid());
            }
            return Ok(());
        }
        self.epoch_records.push(record);
        Ok(())
    }
}

impl PrivateDmRuntime {
    pub(in crate::private_dm_runtime::devices) fn receive_recovery_epoch(
        &mut self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        response: RecoveryEpoch,
    ) -> Result<()> {
        let session_id = response.evidence.request.claim.session_id.clone();
        let session = self.session_ref(&session_id)?;
        session.authorize_recovery_device(sender, roster)?;
        let membership = session.membership.as_ref().ok_or_else(invalid)?;
        let recovery = membership.recovery.as_ref().ok_or_else(invalid)?;
        let source = recovery.source.as_ref().ok_or_else(invalid)?;
        if source.device_id != sender.device_id
            || recovery.round != response.round
            || source.import.request_id != response.request_id
            || session
                .crypto
                .epoch()
                .and_then(|epoch| epoch.checked_add(1))
                != Some(response.evidence.epoch)
            || session.crypto.group_id_bytes().as_ref() != Some(&response.evidence.group_id)
        {
            return Err(invalid());
        }
        let author = response.evidence.author()?;
        let admission = response.evidence.admission(membership);
        verify_authorizer(membership, &author, &response.evidence.roster, &admission)?;
        let validate = || {
            verify_request(&session.crypto, &admission.request)?;
            stage_admission(session, &admission)
        };
        let (crypto, mut next) = match response.evidence.validation_time()? {
            Some(time) => openmls::prelude::Lifetime::with_validation_time(time, validate),
            None => validate(),
        }?;
        next.retain_epoch(response.evidence)?;
        let recovery = next.recovery.as_mut().ok_or_else(invalid)?;
        recovery.required_epoch = recovery.required_epoch.max(admission.epoch);
        recovery.last_rx_ms = now_ms();
        let source = recovery.source.as_mut().ok_or_else(invalid)?;
        source.epoch = source.epoch.max(admission.epoch);
        self.install_device_transition(&session_id, crypto, next)?;
        self.session_mut(&session_id)?.history_last_rx_ms = now_ms();
        // Recovery is already durable. An unavailable author can receive its
        // admission acknowledgement when that same journal retries later.
        let _ = self.send_admission_ack(identity, &author, &admission);
        Ok(())
    }
}
