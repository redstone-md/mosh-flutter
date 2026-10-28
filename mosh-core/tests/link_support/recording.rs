use super::Peer;

impl Peer {
    #[allow(
        dead_code,
        reason = "Manual real-carrier verification archives network metrics only."
    )]
    pub fn archive_network_recording(&self, destination: &std::path::Path) {
        std::fs::create_dir_all(destination).unwrap();
        for entry in std::fs::read_dir(&self.dir).unwrap() {
            let path = entry.unwrap().path();
            if path
                .extension()
                .is_some_and(|extension| extension == "mossrec")
            {
                std::fs::copy(&path, destination.join(path.file_name().unwrap())).unwrap();
            }
        }
    }

    #[allow(
        dead_code,
        reason = "Shared harness: only idle-presence scenarios record publications."
    )]
    pub fn new_recorded_api() -> Self {
        Self::new_installation(true, false, "independent_installation_process", true)
    }

    /// Count this installation's own publications, excluding relayed traffic.
    #[allow(
        dead_code,
        reason = "Shared harness: only idle-presence scenarios read recordings."
    )]
    pub fn publication_count(&self) -> usize {
        let mut count = 0;
        for entry in std::fs::read_dir(&self.dir).unwrap() {
            let path = entry.unwrap().path();
            if path
                .extension()
                .is_none_or(|extension| extension != "mossrec")
            {
                continue;
            }
            let contents = std::fs::read(path).unwrap();
            // The writer flushes each JSON line; its current tail can be partial.
            let Some(end) = contents.iter().rposition(|byte| *byte == b'\n') else {
                continue;
            };
            let complete = std::str::from_utf8(&contents[..end]).unwrap();
            count += complete
                .lines()
                .filter(|line| {
                    let row: serde_json::Value = serde_json::from_str(line).unwrap();
                    row["metric"] == "event" && row["data"]["kind"] == "gossip.publish"
                })
                .count();
        }
        count
    }
}
