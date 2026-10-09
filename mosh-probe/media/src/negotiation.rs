//! Test-only negotiation over trusted parent/worker pipes. Not the Mosh protocol.
use prost::Message;
use rand::{RngCore, rngs::OsRng};
use ringrtc::{
    common::{CallConfig, DataMode, Result},
    protobuf::signaling::ConnectionParametersV4,
    webrtc::{
        peer_connection::PeerConnection,
        sdp_observer::{
            SessionDescription, SrtpCryptoSuite, SrtpKey, create_csd_observer, create_ssd_observer,
        },
    },
};
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct Description {
    pub offer: bool,
    pub parameters: Vec<u8>,
    pub key: Vec<u8>,
    pub salt: Vec<u8>,
}

impl Description {
    pub fn create(pc: &PeerConnection, offer: bool) -> Result<Self> {
        let observer = create_csd_observer(Some(false));
        if offer {
            pc.create_offer(&observer);
        } else {
            pc.create_answer(&observer);
        }
        let parameters =
            observer
                .get_result()?
                .to_v4(Vec::new(), &CallConfig::default(), DataMode::Normal)?;
        let (mut key, mut salt) = (vec![0; 32], vec![0; 12]);
        OsRng.fill_bytes(&mut key);
        OsRng.fill_bytes(&mut salt);
        let description = Self {
            offer,
            parameters: parameters.encode_to_vec(),
            key,
            salt,
        };
        description.install(pc, true)?;
        Ok(description)
    }

    pub fn install(&self, pc: &PeerConnection, local: bool) -> Result<()> {
        if self.key.len() != 32 || self.salt.len() != 12 {
            anyhow::bail!("invalid SRTP key sizes");
        }
        let parameters = ConnectionParametersV4::decode(&*self.parameters)?;
        let config = CallConfig::default();
        let mut description = if self.offer {
            SessionDescription::offer_from_v4(&parameters, &config, local)?
        } else {
            SessionDescription::answer_from_v4(&parameters, &config, local)?
        };
        description.disable_dtls_and_set_srtp_key(&SrtpKey {
            suite: SrtpCryptoSuite::AeadAes256Gcm,
            key: self.key.clone(),
            salt: self.salt.clone(),
        })?;
        let observer = create_ssd_observer();
        if local {
            pc.set_local_description(&observer, description);
        } else {
            pc.set_remote_description(&observer, description);
        }
        observer.get_result()
    }
}
