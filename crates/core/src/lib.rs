//! Burrow core: SSH sessions, independent of any UI.
pub mod ssh;
pub use ssh::{Auth, ConnectOptions, Session};
