//! Public negotiation is authenticated by MLS before the native owner submits it.
use crate::keys::{Agreement, MediaBinding, Role, SrtpKeys};
use prost::Message;
use ringrtc::{
    common::{CallConfig, DataMode, Result},
    protobuf::signaling::ConnectionParametersV4,
    webrtc::{
        peer_connection::PeerConnection,
        sdp_observer::{SessionDescription, SrtpKey, create_csd_observer, create_ssd_observer},
    },
};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Description {
    pub binding: MediaBinding,
    pub offer: bool,
    pub parameters: Vec<u8>,
}

impl Description {
    fn create(
        pc: &PeerConnection,
        binding: &MediaBinding,
        offer: bool,
        public: Vec<u8>,
    ) -> Result<Self> {
        let observer = create_csd_observer(Some(false));
        if offer {
            pc.create_offer(&observer);
        } else {
            pc.create_answer(&observer);
        }
        let parameters =
            observer
                .get_result()?
                .to_v4(public, &CallConfig::default(), DataMode::Normal)?;
        Ok(Self {
            binding: binding.clone(),
            offer,
            parameters: parameters.encode_to_vec(),
        })
    }

    fn parameters(&self) -> Result<ConnectionParametersV4> {
        anyhow::ensure!(
            self.parameters.len() <= 16_384,
            "media description too large"
        );
        let parameters = ConnectionParametersV4::decode(&*self.parameters)?;
        anyhow::ensure!(
            parameters
                .public_key
                .as_ref()
                .is_some_and(|key| key.len() == 32),
            "missing media public key"
        );
        Ok(parameters)
    }

    fn install(
        &self,
        pc: &PeerConnection,
        local: bool,
        key: &SrtpKey,
        audio: &Mutex<[bool; 128]>,
    ) -> Result<()> {
        let parameters = self.parameters()?;
        let config = CallConfig::default();
        let mut description = if self.offer {
            SessionDescription::offer_from_v4(&parameters, &config, local)?
        } else {
            SessionDescription::answer_from_v4(&parameters, &config, local)?
        };
        if local {
            learn_audio_payloads(&description.to_sdp()?, audio);
        }
        description.disable_dtls_and_set_srtp_key(key)?;
        let observer = create_ssd_observer();
        if local {
            pc.set_local_description(&observer, description);
        } else {
            pc.set_remote_description(&observer, description);
        }
        observer.get_result()
    }
}

pub struct Negotiator {
    binding: MediaBinding,
    role: Role,
    agreement: Option<Agreement>,
    local: Option<Description>,
    remote: Option<Description>,
    audio: Arc<Mutex<[bool; 128]>>,
}

impl Negotiator {
    pub fn new(binding: MediaBinding, role: Role, audio: Arc<Mutex<[bool; 128]>>) -> Result<Self> {
        binding.validate()?;
        Ok(Self {
            binding,
            role,
            agreement: Some(Agreement::new()),
            local: None,
            remote: None,
            audio,
        })
    }

    pub fn offer(&mut self, pc: &PeerConnection) -> Result<Description> {
        anyhow::ensure!(
            matches!(self.role, Role::Caller),
            "only caller creates media offer"
        );
        if let Some(local) = &self.local {
            return Ok(local.clone());
        }
        let public = self
            .agreement
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("agreement consumed"))?
            .public_key();
        let local = Description::create(pc, &self.binding, true, public.to_vec())?;
        self.local = Some(local.clone());
        Ok(local)
    }

    pub fn receive(&mut self, pc: &PeerConnection, remote: Description) -> Result<Description> {
        anyhow::ensure!(
            remote.binding == self.binding,
            "media binding differs from selected call"
        );
        if let Some(accepted) = &self.remote {
            anyhow::ensure!(
                accepted == &remote,
                "media description changed after agreement"
            );
            return self
                .local
                .clone()
                .ok_or_else(|| anyhow::anyhow!("missing local description"));
        }
        anyhow::ensure!(
            remote.offer == matches!(self.role, Role::Callee),
            "wrong description role"
        );
        let parameters = remote.parameters()?;
        let agreement = self
            .agreement
            .take()
            .ok_or_else(|| anyhow::anyhow!("agreement consumed"))?;
        let public = agreement.public_key();
        let keys = agreement.finish(
            parameters.public_key.as_ref().unwrap(),
            &self.binding,
            self.role,
        )?;
        let local = self.install(pc, &remote, public, &keys)?;
        self.remote = Some(remote);
        self.local = Some(local.clone());
        Ok(local)
    }

    fn install(
        &self,
        pc: &PeerConnection,
        remote: &Description,
        public: [u8; 32],
        keys: &SrtpKeys,
    ) -> Result<Description> {
        match self.role {
            Role::Caller => {
                let local = self
                    .local
                    .as_ref()
                    .ok_or_else(|| anyhow::anyhow!("offer was not created"))?;
                local.install(pc, true, &keys.offer, &self.audio)?;
                remote.install(pc, false, &keys.answer, &self.audio)?;
                Ok(local.clone())
            }
            Role::Callee => {
                remote.install(pc, false, &keys.offer, &self.audio)?;
                let local = Description::create(pc, &self.binding, false, public.to_vec())?;
                local.install(pc, true, &keys.answer, &self.audio)?;
                Ok(local)
            }
        }
    }

    pub fn ready(&self) -> bool {
        self.remote.is_some()
    }
}

fn learn_audio_payloads(sdp: &str, audio: &Mutex<[bool; 128]>) {
    if let Ok(mut audio) = audio.lock() {
        for line in sdp.lines().filter(|line| line.starts_with("m=audio ")) {
            for payload in line.split_ascii_whitespace().skip(3) {
                if let Ok(payload) = payload.parse::<usize>()
                    && payload < audio.len()
                {
                    audio[payload] = true;
                }
            }
        }
    }
}

#[cfg(test)]
#[path = "negotiation_tests.rs"]
mod tests;
