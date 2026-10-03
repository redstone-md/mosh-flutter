use std::path::{Path, PathBuf};

/// Declare before local handles, or after handle-owning fields, to clean up last.
pub struct TempDirectory(PathBuf);

impl TempDirectory {
    pub fn new(prefix: &str) -> Self {
        let path = std::env::temp_dir().join(format!("{prefix}-{}", rand::random::<u64>()));
        std::fs::create_dir(&path).expect("test directory should be created");
        Self(path)
    }

    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDirectory {
    fn drop(&mut self) {
        if let Err(error) = std::fs::remove_dir_all(&self.0) {
            if error.kind() == std::io::ErrorKind::NotFound {
                return;
            }
            if std::thread::panicking() {
                eprintln!(
                    "test directory cleanup failed ({}): {error}",
                    self.0.display()
                );
            } else {
                panic!(
                    "test directory cleanup failed ({}): {error}",
                    self.0.display()
                );
            }
        }
    }
}
