//! Wire types shared by the desktop app and the sync server.
//! The server only ever sees ciphertext; `kind` is coarse metadata (host, key, snippet).
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Credentials {
    pub email: String,
    /// Key derived on the client from the master password (never the password itself).
    pub auth_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoginResponse {
    pub token: String,
}

/// Vault key encrypted with the user's key-encryption key. Opaque to the server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WrappedVaultKey {
    pub ciphertext: String,
    pub nonce: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Item {
    pub id: String,
    pub kind: String,
    /// Base64 XChaCha20-Poly1305 ciphertext. Empty when `deleted`.
    pub ciphertext: String,
    pub nonce: String,
    pub deleted: bool,
    /// Server-assigned, increasing per user. Ignored on push.
    #[serde(default)]
    pub seq: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Changes {
    pub items: Vec<Item>,
    /// Pass back as `since` on the next pull.
    pub cursor: i64,
}
