//! Stop/waiting observes existing work without constructing a runtime or opening rooms.
use super::*;

impl ChannelRuntime {
    pub(crate) fn download_manifest(
        &mut self,
        target: &str,
        attachment: &str,
    ) -> Result<Option<crate::attachment_runtime::AttachmentManifest>, ChannelRuntimeError> {
        Ok(self
            .channel_mut(target)?
            .transfer
            .download_manifest(attachment))
    }

    pub(crate) fn bind_attachment_admission(
        &mut self,
        target: &str,
        attachment: &str,
        admission: &str,
    ) -> Result<(), ChannelRuntimeError> {
        self.channel_mut(target)?
            .transfer
            .bind_download_admission(attachment, admission)?;
        Ok(())
    }

    pub(crate) fn service(&mut self) {
        if let Err(error) = self
            .drain_inbound()
            .and_then(|_| self.channels.persist_tail().map_err(Into::into))
        {
            dlog::write(
                LogLevel::Warn,
                kinds::SERVICE,
                "channel",
                &error.to_string(),
            );
        }
    }

    pub(crate) fn background_work(&mut self) -> Result<(u32, u32), ChannelRuntimeError> {
        for session in self.channels.values_mut() {
            session.transfer.refresh_execution()?;
        }
        self.channels.persist_tail()?;
        let transfers: usize = self
            .channels
            .values()
            .map(|session| session.transfer.active_user_transfers())
            .sum();
        Ok((0, u32::try_from(transfers).unwrap_or(u32::MAX)))
    }
}
