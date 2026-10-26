//! Stop/waiting observes existing work without constructing a runtime or opening rooms.
use super::*;

impl ChannelRuntime {
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
        self.channels.persist_tail()?;
        let transfers = self
            .channels
            .values()
            .flat_map(|session| session.transfer.views())
            .filter(|view| {
                view.state == crate::conversation::attachments::AttachmentState::Downloading
            })
            .count();
        Ok((0, u32::try_from(transfers).unwrap_or(u32::MAX)))
    }
}
