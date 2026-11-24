//! End-to-end-encrypted sync client for burrow-server.
//!
//! Keys: `master = Argon2id(password, salt(email))`, then HKDF splits it into an
//! auth key (sent to the server, which stores only its Argon2 hash) and a KEK that
//! wraps a random vault key. Every item is sealed with the vault key, so the server
//! only ever sees ciphertext.
//!
//! Merge rules (sync must never lose local data):
//! - Remote changes apply to items that have no unsynced local edits.
//! - When both sides changed an item, the newer edit wins.
//! - A local edit always beats a remote delete; the item comes back for everyone.
use anyhow::{anyhow, bail, Context, Result};
use argon2::{Algorithm, Argon2, Params, Version};
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use burrow_proto::{Changes, Credentials, Item, LoginResponse, WrappedVaultKey};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use hkdf::Hkdf;
use rand::RngCore;
use reqwest::StatusCode;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// A signed-in sync account. The app keeps `token` and `vault_key` in the keychain.
#[derive(Debug, Clone)]
pub struct Account {
    pub server: String,
    pub email: String,
    pub token: String,
    /// Base64 of the 32-byte vault key.
    pub vault_key: String,
}

/// One local record as the app sees it. `data` is the app's own JSON.
#[derive(Debug, Clone, PartialEq)]
pub struct LocalItem {
    pub id: String,
    pub kind: String,
    pub data: String,
    /// Milliseconds since the epoch of the last local change.
    pub updated_at: i64,
    pub deleted: bool,
    /// Changed locally since the last successful push.
    pub dirty: bool,
}

#[derive(Debug, Clone, Default)]
pub struct RoundResult {
    /// Remote changes to write locally (upserts, or deletes when `deleted`).
    pub apply: Vec<LocalItem>,
    /// Ids now on the server; clear their dirty flag (and drop tombstones).
    pub pushed: Vec<String>,
    pub cursor: i64,
}

/// Plaintext inside each item's ciphertext.
#[derive(Serialize, Deserialize)]
struct Sealed {
    data: String,
    updated_at: i64,
}

pub fn normalize_email(email: &str) -> String {
    email.trim().to_lowercase()
}

/// Adds a scheme when missing: plain http for this machine and the local
/// network (where a home server usually has no certificate), https otherwise.
pub fn normalize_server(server: &str) -> String {
    let s = server.trim().trim_end_matches('/');
    if s.starts_with("http://") || s.starts_with("https://") {
        return s.to_string();
    }
    let host = s.split(['/', ':']).next().unwrap_or("").to_lowercase();
    let local = host == "localhost"
        || host.ends_with(".local")
        || !host.contains('.')
        || host.parse::<std::net::Ipv4Addr>().is_ok_and(|ip| ip.is_private() || ip.is_loopback() || ip.is_link_local());
    format!("{}://{s}", if local { "http" } else { "https" })
}

struct Derived {
    auth_key: String,
    kek: [u8; 32],
}

fn derive(email: &str, password: &str) -> Result<Derived> {
    let salt = Sha256::digest(format!("burrow-sync:{email}").as_bytes());
    let params = Params::new(64 * 1024, 3, 1, Some(32)).map_err(|e| anyhow!("{e}"))?;
    let mut master = [0u8; 32];
    Argon2::new(Algorithm::Argon2id, Version::V0x13, params)
        .hash_password_into(password.as_bytes(), &salt, &mut master)
        .map_err(|e| anyhow!("{e}"))?;
    let hk = Hkdf::<Sha256>::new(None, &master);
    let mut auth = [0u8; 32];
    let mut kek = [0u8; 32];
    hk.expand(b"burrow auth", &mut auth).map_err(|e| anyhow!("{e}"))?;
    hk.expand(b"burrow kek", &mut kek).map_err(|e| anyhow!("{e}"))?;
    Ok(Derived { auth_key: hex::encode(auth), kek })
}

fn seal(key: &[u8], aad: &[u8], plain: &[u8]) -> Result<(String, String)> {
    let cipher = XChaCha20Poly1305::new_from_slice(key).map_err(|e| anyhow!("{e}"))?;
    let mut nonce = [0u8; 24];
    rand::thread_rng().fill_bytes(&mut nonce);
    let ct = cipher
        .encrypt(XNonce::from_slice(&nonce), Payload { msg: plain, aad })
        .map_err(|_| anyhow!("encryption failed"))?;
    Ok((B64.encode(ct), B64.encode(nonce)))
}

fn open(key: &[u8], aad: &[u8], ciphertext: &str, nonce: &str) -> Result<Vec<u8>> {
    let cipher = XChaCha20Poly1305::new_from_slice(key).map_err(|e| anyhow!("{e}"))?;
    let nonce = B64.decode(nonce)?;
    if nonce.len() != 24 {
        bail!("bad nonce");
    }
    cipher
        .decrypt(XNonce::from_slice(&nonce), Payload { msg: &B64.decode(ciphertext)?, aad })
        .map_err(|_| anyhow!("could not decrypt"))
}

fn http() -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(20))
        .build()
        .expect("http client")
}

async fn check(res: reqwest::Response) -> Result<reqwest::Response> {
    let status = res.status();
    if status.is_success() {
        return Ok(res);
    }
    let body = res.text().await.unwrap_or_default();
    Err(match status {
        StatusCode::UNAUTHORIZED => anyhow!("Wrong email or password, or you were signed out."),
        StatusCode::CONFLICT => anyhow!("An account with that email already exists. Sign in instead."),
        _ => anyhow!("Server error {status}: {body}"),
    })
}

fn net(e: reqwest::Error) -> anyhow::Error {
    if e.is_connect() || e.is_timeout() {
        anyhow!("Can't reach the sync server.")
    } else {
        anyhow!("{e}")
    }
}

/// Creates an account and a fresh vault key.
pub async fn register(server: &str, email: &str, password: &str) -> Result<Account> {
    let server = normalize_server(server);
    let email = normalize_email(email);
    if password.chars().count() < 8 {
        bail!("Use at least 8 characters for the sync password.");
    }
    let d = derive(&email, password)?;
    let c = http();
    let res = c
        .post(format!("{server}/v1/auth/register"))
        .json(&Credentials { email: email.clone(), auth_key: d.auth_key })
        .send()
        .await
        .map_err(net)?;
    let token = check(res).await?.json::<LoginResponse>().await?.token;
    let vault_key = put_new_vault_key(&c, &server, &token, &d.kek).await?;
    Ok(Account { server, email, token, vault_key })
}

async fn put_new_vault_key(c: &reqwest::Client, server: &str, token: &str, kek: &[u8; 32]) -> Result<String> {
    let mut vk = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut vk);
    let (ciphertext, nonce) = seal(kek, b"vault key", &vk)?;
    let res = c
        .put(format!("{server}/v1/vault/key"))
        .bearer_auth(token)
        .json(&WrappedVaultKey { ciphertext, nonce })
        .send()
        .await
        .map_err(net)?;
    check(res).await?;
    Ok(B64.encode(vk))
}

/// Signs in and unwraps the vault key with the password.
pub async fn login(server: &str, email: &str, password: &str) -> Result<Account> {
    let server = normalize_server(server);
    let email = normalize_email(email);
    let d = derive(&email, password)?;
    let c = http();
    let res = c
        .post(format!("{server}/v1/auth/login"))
        .json(&Credentials { email: email.clone(), auth_key: d.auth_key })
        .send()
        .await
        .map_err(net)?;
    let token = check(res).await?.json::<LoginResponse>().await?.token;
    let res = c.get(format!("{server}/v1/vault/key")).bearer_auth(&token).send().await.map_err(net)?;
    let wrapped: Option<WrappedVaultKey> = check(res).await?.json().await?;
    let vault_key = match wrapped {
        Some(w) => B64.encode(open(&d.kek, b"vault key", &w.ciphertext, &w.nonce).context("unwrap vault key")?),
        // Registered but the key upload never finished.
        None => put_new_vault_key(&c, &server, &token, &d.kek).await?,
    };
    Ok(Account { server, email, token, vault_key })
}

/// Deletes the account and everything stored for it on the server.
pub async fn delete_account(server: &str, token: &str) -> Result<()> {
    let res = http()
        .delete(format!("{}/v1/account", normalize_server(server)))
        .bearer_auth(token)
        .send()
        .await
        .map_err(net)?;
    check(res).await?;
    Ok(())
}

/// Pulls remote changes since `cursor`, merges them with `local`, and pushes local edits.
/// `local` should hold every local item, including tombstones of deleted ones.
pub async fn sync_round(account: &Account, cursor: i64, local: Vec<LocalItem>) -> Result<RoundResult> {
    let key = B64.decode(&account.vault_key)?;
    let c = http();
    let server = normalize_server(&account.server);

    // Pull everything new, page by page.
    let mut remote = Vec::new();
    let mut since = cursor;
    loop {
        let res = c
            .get(format!("{server}/v1/items"))
            .query(&[("since", since)])
            .bearer_auth(&account.token)
            .send()
            .await
            .map_err(net)?;
        let ch: Changes = check(res).await?.json().await?;
        let done = ch.items.is_empty() || ch.cursor == since;
        since = ch.cursor;
        remote.extend(ch.items);
        if done {
            break;
        }
    }
    let mut decoded = Vec::with_capacity(remote.len());
    for it in remote {
        let plain = open(&key, it.id.as_bytes(), &it.ciphertext, &it.nonce)
            .with_context(|| format!("item {}", it.id))?;
        let s: Sealed = serde_json::from_slice(&plain)?;
        decoded.push(LocalItem {
            id: it.id,
            kind: it.kind,
            data: s.data,
            updated_at: s.updated_at,
            deleted: it.deleted,
            dirty: false,
        });
    }

    let (apply, to_push) = merge(local, decoded);

    let mut pushed = Vec::new();
    if !to_push.is_empty() {
        let mut items = Vec::with_capacity(to_push.len());
        for l in &to_push {
            let plain = serde_json::to_vec(&Sealed {
                data: if l.deleted { String::new() } else { l.data.clone() },
                updated_at: l.updated_at,
            })?;
            let (ciphertext, nonce) = seal(&key, l.id.as_bytes(), &plain)?;
            items.push(Item { id: l.id.clone(), kind: l.kind.clone(), ciphertext, nonce, deleted: l.deleted, seq: 0 });
        }
        let res = c
            .put(format!("{server}/v1/items"))
            .bearer_auth(&account.token)
            .json(&items)
            .send()
            .await
            .map_err(net)?;
        check(res).await?;
        pushed = to_push.into_iter().map(|l| l.id).collect();
    }
    // Keep the pull cursor (not the push one) so changes other devices made in
    // between are not skipped. Our own pushes come back once and merge as no-ops.
    Ok(RoundResult { apply, pushed, cursor: since })
}

/// Pure merge. Returns (remote changes to apply locally, local items to push).
pub fn merge(local: Vec<LocalItem>, remote: Vec<LocalItem>) -> (Vec<LocalItem>, Vec<LocalItem>) {
    use std::collections::HashMap;
    // Latest remote version per id.
    let mut latest: HashMap<String, LocalItem> = HashMap::new();
    for r in remote {
        latest.insert(r.id.clone(), r);
    }
    let mut by_id: HashMap<String, LocalItem> = local.into_iter().map(|l| (l.id.clone(), l)).collect();
    let mut apply = Vec::new();
    for (id, r) in latest {
        match by_id.get(&id) {
            None => {
                if !r.deleted {
                    apply.push(r);
                }
            }
            Some(l) if !l.dirty => {
                // Skip echoes of what we already have.
                let same = l.deleted == r.deleted && l.updated_at == r.updated_at && (r.deleted || l.data == r.data);
                if !same {
                    apply.push(r);
                }
            }
            Some(l) => {
                let local_wins = if r.deleted && !l.deleted {
                    true // never let a remote delete wipe an unsynced local edit
                } else {
                    l.updated_at >= r.updated_at
                };
                if !local_wins {
                    by_id.remove(&id);
                    apply.push(r);
                }
            }
        }
    }
    let mut to_push: Vec<LocalItem> = by_id.into_values().filter(|l| l.dirty).collect();
    to_push.sort_by(|a, b| a.id.cmp(&b.id));
    apply.sort_by(|a, b| a.id.cmp(&b.id));
    (apply, to_push)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn it(id: &str, data: &str, t: i64, deleted: bool, dirty: bool) -> LocalItem {
        LocalItem { id: id.into(), kind: "host".into(), data: data.into(), updated_at: t, deleted, dirty }
    }

    #[test]
    fn remote_delete_never_beats_local_edit() {
        let (apply, push) = merge(vec![it("a", "edited", 5, false, true)], vec![it("a", "", 9, true, false)]);
        assert!(apply.is_empty());
        assert_eq!(push.len(), 1);
    }

    #[test]
    fn newer_edit_wins() {
        let (apply, push) = merge(vec![it("a", "old", 1, false, true)], vec![it("a", "new", 2, false, false)]);
        assert_eq!(apply[0].data, "new");
        assert!(push.is_empty());
        let (apply, push) = merge(vec![it("a", "mine", 3, false, true)], vec![it("a", "theirs", 2, false, false)]);
        assert!(apply.is_empty());
        assert_eq!(push[0].data, "mine");
    }

    #[test]
    fn clean_items_follow_remote_and_echoes_are_ignored() {
        let (apply, _) = merge(vec![it("a", "x", 1, false, false)], vec![it("a", "x", 1, false, false)]);
        assert!(apply.is_empty());
        let (apply, _) = merge(vec![it("a", "x", 1, false, false)], vec![it("a", "", 2, true, false)]);
        assert!(apply[0].deleted);
    }

    #[test]
    fn server_scheme_defaults() {
        assert_eq!(normalize_server("localhost:8080/"), "http://localhost:8080");
        assert_eq!(normalize_server("192.168.1.5:8080"), "http://192.168.1.5:8080");
        assert_eq!(normalize_server("mac-mini.local:8080"), "http://mac-mini.local:8080");
        assert_eq!(normalize_server("sync.example.com"), "https://sync.example.com");
        assert_eq!(normalize_server("http://sync.example.com"), "http://sync.example.com");
    }

    #[test]
    fn crypto_round_trip_binds_id() {
        let key = [7u8; 32];
        let (ct, n) = seal(&key, b"id1", b"hello").unwrap();
        assert_eq!(open(&key, b"id1", &ct, &n).unwrap(), b"hello");
        assert!(open(&key, b"id2", &ct, &n).is_err());
    }
}
