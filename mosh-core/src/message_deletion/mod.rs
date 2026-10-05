//! Message identities and durable deletion, shared by conversation owners.
mod application;
pub(crate) mod authority;
mod book;
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
pub(crate) mod types;
pub(crate) use book::{DeletionBook, DeletionRecord};

pub use origin::MessageOrigin;
pub use types::{DeleteScope, DeletionMarker, DeletionStatus, MessageMetadata};

#[cfg(test)]
mod fragment_tests;
