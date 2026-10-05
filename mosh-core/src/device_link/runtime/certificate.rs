use super::*;
use crate::device_link::{names_wire::NameMessage, roster::invalid};

impl DeviceLinkRuntime {
    pub(super) fn receive_certificate(
        &mut self,
        sender: &DeviceDescriptor,
        message: NameMessage,
    ) -> Result<()> {
        match message {
            NameMessage::CertificateRequest => {
                if let Some(certificate) = self.identity.account_certificate()? {
                    let certificate =
                        certificate.issue(&sender.signing_public_key, &self.identity.key())?;
                    self.send_names(sender, NameMessage::Certificate { certificate });
                }
            }
            NameMessage::Certificate { certificate } => {
                certificate.verify()?;
                if certificate.root != self.identity.roster().user_id()
                    || certificate.subject() != self.identity.device().signing_public_key
                    || certificate.issuer() != Some(sender.signing_public_key.as_str())
                {
                    return Err(invalid());
                }
                if self.identity.account_certificate()?.is_none() {
                    let mut record = self.identity.record.clone();
                    record.account_certificate = Some(certificate);
                    self.identity.update(record)?;
                }
            }
            _ => return Err(invalid()),
        }
        Ok(())
    }
}
