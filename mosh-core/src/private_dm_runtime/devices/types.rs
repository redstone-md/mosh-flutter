use super::{invalid, proof::IdentityClaim, DM_USERS, INITIAL_CLIENTS};
use crate::device_link::roster::DeviceRoster;
use crate::private_dm_runtime::PrivateDmRuntimeError;
use serde::{Deserialize, Serialize};

pub(super) type Result<T> = std::result::Result<T, PrivateDmRuntimeError>;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct DmTopology {
    pub own_user_id: String,
    pub clients: Vec<IdentityClaim>,
    pub rosters: Vec<DeviceRoster>,
}

impl DmTopology {
    pub fn own(&self, signer: &str) -> bool {
        self.client(signer)
            .is_some_and(|client| client.roster.user_id() == self.own_user_id)
    }

    pub fn client(&self, signer: &str) -> Option<&IdentityClaim> {
        self.clients
            .iter()
            .find(|client| client.mls_signer == signer)
    }

    pub fn roster(&self, user: &str) -> Option<&DeviceRoster> {
        self.rosters.iter().find(|roster| roster.user_id() == user)
    }

    pub fn update_roster(&mut self, roster: DeviceRoster) -> Result<()> {
        if let Some(base) = self.roster(&roster.user_id()) {
            if !roster.extends(base).map_err(|_| invalid())? {
                return Err(invalid());
            }
        } else if self.rosters.len() >= DM_USERS {
            return Err(invalid());
        }
        self.rosters
            .retain(|base| base.user_id() != roster.user_id());
        self.rosters.push(roster);
        Ok(())
    }

    pub fn add_client(&mut self, claim: IdentityClaim) -> Result<()> {
        claim.verify(&claim.session_id)?;
        match self.roster(&claim.roster.user_id()) {
            Some(base) if base.extends(&claim.roster).map_err(|_| invalid())? => {
                if !base
                    .authorizes_admitted(&claim.roster, &claim.device()?)
                    .map_err(|_| invalid())?
                {
                    return Err(invalid());
                }
            }
            _ => self.update_roster(claim.roster.clone())?,
        }
        if let Some(existing) = self.client(&claim.mls_signer) {
            if existing.device_id != claim.device_id
                || existing.roster.user_id() != claim.roster.user_id()
            {
                return Err(invalid());
            }
            self.clients
                .retain(|client| client.mls_signer != claim.mls_signer);
        } else if self
            .clients
            .iter()
            .any(|client| client.device_id == claim.device_id)
        {
            return Err(invalid());
        }
        self.clients.push(claim);
        Ok(())
    }

    pub fn validate(&self, session: &str, signers: &[String]) -> Result<()> {
        if self.rosters.len() != DM_USERS || self.roster(&self.own_user_id).is_none() {
            return Err(invalid());
        }
        let mut checked = Self {
            own_user_id: self.own_user_id.clone(),
            clients: Vec::new(),
            rosters: Vec::new(),
        };
        for claim in &self.clients {
            claim.verify(session)?;
            let current = self.roster(&claim.roster.user_id()).ok_or_else(invalid)?;
            if !current
                .authorizes_admitted(&claim.roster, &claim.device()?)
                .map_err(|_| invalid())?
            {
                return Err(invalid());
            }
            checked.add_client(claim.clone())?;
        }
        let mut expected: Vec<_> = self
            .clients
            .iter()
            .map(|client| client.mls_signer.clone())
            .collect();
        let mut actual = signers.to_vec();
        expected.sort();
        actual.sort();
        if expected != actual || checked.clients.len() != self.clients.len() {
            return Err(invalid());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct DeviceMembership {
    pub(super) topology: DmTopology,
    pub(super) joining: Option<PendingJoin>,
    pub(super) delivery: Option<AdmissionJournal>,
    #[serde(default)]
    pub(super) receipt_targets: std::collections::HashMap<String, Vec<String>>,
    #[serde(default)]
    pub(super) delivered_ids: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) history_import: Option<super::history::HistoryImport>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub(super) history_exports: Vec<super::history::HistoryExport>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) recovery: Option<super::recovery::Recovery>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub(super) recovery_exports: Vec<super::recovery::RecoveryExport>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub(super) epoch_records: Vec<super::recovery::EpochRecord>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub(super) removals: Vec<super::revocation::RemovalJournal>,
    #[serde(default)]
    pub(super) revoked: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub(super) pending_rosters: Vec<DeviceRoster>,
}

impl DeviceMembership {
    pub(crate) fn is_joining(&self) -> bool {
        self.joining.is_some()
    }

    pub(crate) fn peer_delivered(&self, id: &str) -> bool {
        self.delivered_ids.iter().any(|seen| seen == id)
    }

    pub(super) fn live(&self) -> bool {
        (self.topology.clients.len() > INITIAL_CLIENTS
            || !self.removals.is_empty()
            || self.recovery.is_some())
            && self.joining.is_none()
    }

    pub(super) fn client(&self, signer: &str) -> Option<&IdentityClaim> {
        self.topology.client(signer)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct DmOffer {
    pub session_id: String,
    pub mesh_id: String,
    pub fingerprint: String,
    pub invite_uri: Option<String>,
    pub group_id: Vec<u8>,
    pub own_name: String,
    pub peer_name: String,
    pub topology: DmTopology,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct JoinRequest {
    pub request_id: String,
    pub claim: IdentityClaim,
    pub key_package: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct PendingJoin {
    pub request: JoinRequest,
    pub authorizer_peer: String,
    pub group_id: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct Admission {
    pub request: JoinRequest,
    pub commit: Vec<u8>,
    pub welcome: Vec<u8>,
    pub tree: Vec<u8>,
    pub topology: DmTopology,
    pub group_id: Vec<u8>,
    pub epoch: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recovery_authorization: Option<super::recovery::EpochAuthorization>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct AdmissionJournal {
    pub admission: Admission,
    pub waiting: Vec<String>,
}

impl AdmissionJournal {
    // One available counterpart accepts the epoch for its user. The joining
    // client must also save its Welcome; other clients recover retained commits.
    pub fn accepted(&self) -> Result<bool> {
        let joining = self.admission.request.claim.device()?;
        if self.waiting.contains(&joining.moss_peer_id) {
            return Ok(false);
        }
        let user = self.admission.request.claim.roster.user_id();
        for client in &self.admission.topology.clients {
            if client.roster.user_id() != user
                && !self.waiting.contains(&client.device()?.moss_peer_id)
            {
                return Ok(true);
            }
        }
        Ok(false)
    }

    pub fn new(admission: Admission, local_device: &str) -> Result<Self> {
        let waiting = admission
            .topology
            .clients
            .iter()
            .map(IdentityClaim::device)
            .collect::<Result<Vec<_>>>()?
            .into_iter()
            .filter(|device| device.device_id != local_device)
            .map(|device| device.moss_peer_id)
            .collect();
        Ok(Self { admission, waiting })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) enum DeviceMessage {
    Removal(super::revocation::RemovalRecord),
    RemovalAck {
        session_id: String,
        epoch: u64,
        evidence: String,
    },
    Offer(DmOffer),
    Join(JoinRequest),
    Admission(Admission),
    HistoryRequest(super::history::HistoryRequest),
    HistoryBatch(super::history::HistoryBatch),
    RecoveryProbe(super::recovery::RecoveryProbe),
    RecoveryOffer(super::recovery::RecoveryOffer),
    RecoveryPull(super::recovery::RecoveryPull),
    RecoveryBatch(super::recovery::RecoveryBatch),
    RecoveryEpoch(super::recovery::RecoveryEpoch),
    RecoveryRemoval(super::recovery::RecoveryRemoval),
    Ack {
        session_id: String,
        request_id: String,
        epoch: u64,
    },
}

impl DeviceMembership {
    pub(crate) fn deletion_accounts(&self) -> std::collections::BTreeMap<String, String> {
        self.topology
            .clients
            .iter()
            .map(|client| (client.mls_signer.clone(), client.roster.user_id()))
            .collect()
    }
}
