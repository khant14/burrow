//! Burrow core: SSH sessions and the sync client, independent of any UI.
pub mod ssh;
pub mod sync;
pub use ssh::{Auth, ConnectOptions, Session};
