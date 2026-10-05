#[derive(Debug)]
pub enum DeletionError {
    InvalidInput(String),
    PermissionDenied,
    Revoked,
    Persistence(String),
    Internal(String),
}

impl std::fmt::Display for DeletionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidInput(message) | Self::Persistence(message) | Self::Internal(message) => {
                f.write_str(message)
            }
            Self::PermissionDenied => f.write_str("deletion permission denied"),
            Self::Revoked => f.write_str("revoked device cannot delete messages"),
        }
    }
}
impl std::error::Error for DeletionError {}
