//! Actual retained user work; does not list/poll snapshots or mark messages read.
use super::*;

impl PrivateDmRuntime {
    pub(crate) fn background_work(&mut self) -> Result<(u32, u32), String> {
        self.sessions.persist_tail().map_err(|e| e.to_string())?;
        let mut calls = 0;
        let mut transfers = 0;
        for session in self.sessions.values() {
            calls += u32::from(
                session
                    .call
                    .as_ref()
                    .is_some_and(|call| call.phase != CallPhase::Ringing),
            );
            transfers += session
                .transfer
                .views()
                .iter()
                .filter(|view| view.state == AttachmentState::Downloading)
                .count() as u32;
        }
        Ok((calls, transfers))
    }
}
