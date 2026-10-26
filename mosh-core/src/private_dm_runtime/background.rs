//! Actual retained user work; does not list/poll snapshots or mark messages read.
use super::*;

impl PrivateDmRuntime {
    pub(crate) fn background_work(&mut self) -> Result<(u32, u32), String> {
        self.sessions.persist_tail().map_err(|e| e.to_string())?;
        self.sync_background_calls()?;
        let mut calls = 0;
        let mut transfers = 0;
        for session in self.sessions.values_mut() {
            session
                .transfer
                .refresh_execution()
                .map_err(|error| error.to_string())?;
            calls += u32::from(
                session
                    .call
                    .as_ref()
                    .is_some_and(|call| call.phase != CallPhase::Ringing),
            );
            transfers += session.transfer.active_user_transfers() as u32;
        }
        Ok((calls, transfers))
    }
}
