//! Preserve v1 history signatures; updated peers authenticate metadata separately.
use super::{
    invalid,
    proof::verify,
    types::{DeviceMessage, Result},
};
use crate::{device_link::identity::DeviceIdentity, message_deletion::MessageMetadata};
use ed25519_dalek::Signer;
use serde::{Deserialize, Serialize};

const CONTEXT: &[u8] = b"mosh-dm-history-metadata-v1\0";

#[derive(Serialize, Deserialize)]
pub(super) struct HistoryMetadata {
    records: Vec<Option<MessageMetadata>>,
    fragment: Option<MessageMetadata>,
    signature: String,
}

fn batch(message: &mut DeviceMessage) -> Option<&mut super::history::HistoryBatch> {
    match message {
        DeviceMessage::HistoryBatch(batch) => Some(batch),
        DeviceMessage::RecoveryBatch(response) => Some(&mut response.batch),
        _ => None,
    }
}

impl HistoryMetadata {
    pub fn detach(message: &mut DeviceMessage) -> Option<Self> {
        let batch = batch(message)?;
        let records: Vec<_> = batch
            .records
            .iter_mut()
            .map(|r| r.metadata.take())
            .collect();
        let fragment = batch
            .fragment
            .as_mut()
            .and_then(|f| f.record.metadata.take());
        if records.iter().all(Option::is_none) && fragment.is_none() {
            return None;
        }
        Some(Self {
            records,
            fragment,
            signature: String::new(),
        })
    }

    fn input(&self, primary_signature: &str) -> Result<Vec<u8>> {
        let mut bytes = CONTEXT.to_vec();
        bytes.extend(
            serde_json::to_vec(&(primary_signature, &self.records, &self.fragment))
                .map_err(|_| invalid())?,
        );
        Ok(bytes)
    }

    pub fn sign(&mut self, identity: &DeviceIdentity, primary_signature: &str) -> Result<()> {
        self.signature = hex::encode(
            identity
                .key()
                .sign(&self.input(primary_signature)?)
                .to_bytes(),
        );
        Ok(())
    }

    pub fn restore(
        self,
        message: &mut DeviceMessage,
        key: &str,
        primary_signature: &str,
    ) -> Result<()> {
        verify(key, &self.signature, &self.input(primary_signature)?)?;
        let batch = batch(message).ok_or_else(invalid)?;
        if self.records.len() != batch.records.len()
            || (self.fragment.is_some() && batch.fragment.is_none())
        {
            return Err(invalid());
        }
        for (record, metadata) in batch.records.iter_mut().zip(self.records) {
            record.metadata = metadata;
        }
        if let Some(fragment) = &mut batch.fragment {
            fragment.record.metadata = self.fragment;
        }
        Ok(())
    }
}
