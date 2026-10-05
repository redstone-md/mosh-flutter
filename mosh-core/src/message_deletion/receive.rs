use super::{authority::DeletionAuthority, protocol::DeletionMessage, shared, DeletionBook};
use crate::conversation::{
    message_log::{ConversationMessage, MessageLog},
    transfer::Transfer,
};
use crate::outbound_delivery::OutboundAttemptRecord;
use std::collections::HashMap;

pub(crate) struct DeletionContext<'a, M> {
    pub book: &'a mut DeletionBook,
    pub log: &'a mut MessageLog<M>,
    pub attempts: &'a mut HashMap<String, OutboundAttemptRecord>,
    pub transfer: &'a mut Transfer,
}

impl<M: ConversationMessage> DeletionContext<'_, M> {
    pub fn receive(
        &mut self,
        message: DeletionMessage,
        carrier: &str,
        authority: &DeletionAuthority,
        sign: impl Fn(&[u8]) -> Result<String, String>,
    ) -> Result<Vec<DeletionMessage>, String> {
        if !authority.member(carrier) {
            return Err("unknown deletion carrier".into());
        }
        let Some(message) = self.book.assemble(carrier, message)? else {
            return Ok(Vec::new());
        };
        match message {
            DeletionMessage::Fragment(_) => Err("unexpected deletion fragment".into()),
            DeletionMessage::Request { after, digest } => {
                self.receive_request(after, digest, authority)
            }
            DeletionMessage::State { records, next } => {
                self.receive_state(records, next, carrier, authority, sign)
            }
            DeletionMessage::Ack {
                key,
                acknowledgement,
            } => {
                let record = self.book.records.values().find(|r| {
                    r.request.as_ref().is_some_and(|q| {
                        q.digest().ok().as_deref() == Some(&acknowledgement.request_digest)
                    })
                });
                if let Some(request) = record.and_then(|r| r.request.as_ref()) {
                    authority.validate(record.unwrap(), carrier)?;
                    if acknowledgement.actor != carrier
                        || !authority.may_ack_with_proof(
                            request,
                            carrier,
                            acknowledgement.ownership.as_deref(),
                        )
                    {
                        return Err("ineligible acknowledgement carrier".into());
                    }
                    shared::acknowledge(self, &key, acknowledgement)?;
                }
                Ok(Vec::new())
            }
        }
    }

    fn receive_state(
        &mut self,
        records: Vec<super::DeletionRecord>,
        next: Option<String>,
        carrier: &str,
        authority: &DeletionAuthority,
        sign: impl Fn(&[u8]) -> Result<String, String>,
    ) -> Result<Vec<DeletionMessage>, String> {
        if records.len() > 16 || next.as_ref().is_some_and(|n| n.len() > 1024) {
            return Err("deletion page too large".into());
        }
        let mut replies = Vec::new();
        for record in records {
            let record = self.currently_admissible(record, carrier, authority)?;
            let may_ack = authority.may_ack(
                record.request.as_ref().ok_or("missing request")?,
                &authority.local.key,
            );
            if let Some(ack) = shared::accept(self, &record, &authority.local, may_ack, &sign)? {
                replies.push(ack);
            }
        }
        if next.is_some() {
            replies.push(DeletionMessage::Request {
                after: next,
                digest: None,
            });
        }
        Ok(replies)
    }

    fn currently_admissible(
        &self,
        record: super::DeletionRecord,
        carrier: &str,
        authority: &DeletionAuthority,
    ) -> Result<super::DeletionRecord, String> {
        let request = shared::verify_record(&record, &self.book.context)?;
        if authority.validate(&record, carrier).is_ok() {
            return Ok(record);
        }
        if record.status != super::DeletionStatus::Confirmed {
            authority.validate(&record, carrier)?;
        }
        // Historical receipt membership may be unavailable. Re-admit under
        // current rights and issue our own durable receipt instead of trusting it.
        let pending = shared::canonical(request.clone(), super::DeletionStatus::Pending, None)?;
        authority.validate(&pending, carrier)?;
        Ok(pending)
    }
}

impl<M: ConversationMessage> DeletionContext<'_, M> {
    fn receive_request(
        &self,
        after: Option<String>,
        digest: Option<String>,
        authority: &DeletionAuthority,
    ) -> Result<Vec<DeletionMessage>, String> {
        let local_digest = shared::digest(self.book, authority)?;
        if after.is_none() && digest.as_deref() == Some(&local_digest) {
            return Ok(Vec::new());
        }
        let mut replies = vec![shared::page(self.book, after.as_deref(), authority)];
        if after.is_none() && digest.is_some() {
            replies.push(DeletionMessage::Request {
                after: None,
                digest: Some(local_digest),
            });
        }
        Ok(replies)
    }
}
