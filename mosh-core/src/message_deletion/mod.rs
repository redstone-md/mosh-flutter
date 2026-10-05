//! Message identities and durable deletion, shared by conversation owners.
mod application;
pub(crate) use application::apply;
mod personal;
pub(crate) use personal::delete_for_me;
pub(crate) mod authority;
mod book;
pub(crate) mod correlation;
mod error;
pub use error::DeletionError;
pub(crate) mod cipher;
pub(crate) mod fragment_buffer;
pub(crate) mod fragments;
pub(crate) mod lifecycle;
pub(crate) mod ownership;
pub(crate) mod protocol;
mod receive;
pub(crate) mod shared;
pub(crate) mod snapshot;
pub(crate) use receive::DeletionContext;
pub(crate) mod origin;
mod target;
pub(crate) use target::correlate_history_text;
pub(crate) mod types;
pub(crate) use book::{DeletionBook, DeletionRecord};

pub use origin::MessageOrigin;
pub use types::{DeleteScope, DeletionMarker, DeletionStatus, MessageMetadata};

#[cfg(test)]
mod fragment_tests;
#[cfg(test)]
mod ownership_tests;
#[cfg(test)]
mod policy_tests;
