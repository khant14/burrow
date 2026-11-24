//! Burrow sync server: stores encrypted blobs per user. It never sees plaintext.
use std::sync::{Arc, Mutex};

use argon2::password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use axum::extract::{Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use burrow_proto::{Changes, Credentials, Item, LoginResponse, WrappedVaultKey};
use rand::RngCore;
use rusqlite::{params, Connection, OptionalExtension};
use serde::Deserialize;

type Db = Arc<Mutex<Connection>>;
type ApiResult<T> = Result<T, (StatusCode, String)>;

fn err<E: std::fmt::Display>(e: E) -> (StatusCode, String) {
    (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
}

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, email TEXT UNIQUE NOT NULL, auth_hash TEXT NOT NULL,
  vault_key TEXT, vault_nonce TEXT, seq INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS tokens (token TEXT PRIMARY KEY, user_id INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS items (user_id INTEGER NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL,
  ciphertext TEXT NOT NULL, nonce TEXT NOT NULL, deleted INTEGER NOT NULL, seq INTEGER NOT NULL,
  PRIMARY KEY (user_id, id));
";

#[tokio::main]
async fn main() {
    let path = std::env::var("BURROW_DB").unwrap_or_else(|_| "burrow.db".into());
    let addr = std::env::var("BURROW_ADDR").unwrap_or_else(|_| "0.0.0.0:8080".into());
    let conn = Connection::open(path).expect("open db");
    conn.execute_batch(SCHEMA).expect("migrate");
    let app = router(Arc::new(Mutex::new(conn)));
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    println!("burrow-server listening on {addr}");
    axum::serve(listener, app).await.unwrap();
}

fn router(db: Db) -> Router {
    Router::new()
        .route("/healthz", get(|| async { "ok" }))
        .route("/v1/auth/register", post(register))
        .route("/v1/auth/login", post(login))
        .route("/v1/account", delete(delete_account))
        .route("/v1/vault/key", get(get_vault_key).put(put_vault_key))
        .route("/v1/items", get(pull).put(push))
        .with_state(db)
}

fn new_token(conn: &Connection, user_id: i64) -> ApiResult<String> {
    let mut b = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut b);
    let token = hex::encode(b);
    conn.execute("INSERT INTO tokens VALUES (?1, ?2)", params![token, user_id]).map_err(err)?;
    Ok(token)
}

fn user_from(headers: &HeaderMap, conn: &Connection) -> ApiResult<i64> {
    let token = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .ok_or((StatusCode::UNAUTHORIZED, "missing token".into()))?;
    conn.query_row("SELECT user_id FROM tokens WHERE token = ?1", [token], |r| r.get(0))
        .optional()
        .map_err(err)?
        .ok_or((StatusCode::UNAUTHORIZED, "invalid token".into()))
}

async fn register(State(db): State<Db>, Json(c): Json<Credentials>) -> ApiResult<Json<LoginResponse>> {
    let salt = SaltString::generate(&mut OsRng);
    let hash = Argon2::default().hash_password(c.auth_key.as_bytes(), &salt).map_err(err)?.to_string();
    let conn = db.lock().unwrap();
    conn.execute("INSERT INTO users (email, auth_hash) VALUES (?1, ?2)", params![c.email, hash])
        .map_err(|_| (StatusCode::CONFLICT, "email taken".into()))?;
    let token = new_token(&conn, conn.last_insert_rowid())?;
    Ok(Json(LoginResponse { token }))
}

async fn login(State(db): State<Db>, Json(c): Json<Credentials>) -> ApiResult<Json<LoginResponse>> {
    let conn = db.lock().unwrap();
    let row: Option<(i64, String)> = conn
        .query_row("SELECT id, auth_hash FROM users WHERE email = ?1", [&c.email], |r| Ok((r.get(0)?, r.get(1)?)))
        .optional()
        .map_err(err)?;
    let denied = || (StatusCode::UNAUTHORIZED, "bad credentials".to_string());
    let (id, hash) = row.ok_or_else(denied)?;
    let parsed = PasswordHash::new(&hash).map_err(err)?;
    Argon2::default().verify_password(c.auth_key.as_bytes(), &parsed).map_err(|_| denied())?;
    Ok(Json(LoginResponse { token: new_token(&conn, id)? }))
}

async fn get_vault_key(State(db): State<Db>, headers: HeaderMap) -> ApiResult<Json<Option<WrappedVaultKey>>> {
    let conn = db.lock().unwrap();
    let uid = user_from(&headers, &conn)?;
    let key = conn
        .query_row("SELECT vault_key, vault_nonce FROM users WHERE id = ?1", [uid], |r| {
            Ok(match (r.get::<_, Option<String>>(0)?, r.get::<_, Option<String>>(1)?) {
                (Some(ciphertext), Some(nonce)) => Some(WrappedVaultKey { ciphertext, nonce }),
                _ => None,
            })
        })
        .map_err(err)?;
    Ok(Json(key))
}

async fn put_vault_key(State(db): State<Db>, headers: HeaderMap, Json(k): Json<WrappedVaultKey>) -> ApiResult<StatusCode> {
    let conn = db.lock().unwrap();
    let uid = user_from(&headers, &conn)?;
    conn.execute("UPDATE users SET vault_key = ?1, vault_nonce = ?2 WHERE id = ?3", params![k.ciphertext, k.nonce, uid])
        .map_err(err)?;
    Ok(StatusCode::NO_CONTENT)
}

/// Deletes the account and everything stored for it (App Store guideline 5.1.1(v)).
async fn delete_account(State(db): State<Db>, headers: HeaderMap) -> ApiResult<StatusCode> {
    let mut conn = db.lock().unwrap();
    let uid = user_from(&headers, &conn)?;
    let tx = conn.transaction().map_err(err)?;
    tx.execute("DELETE FROM items WHERE user_id = ?1", [uid]).map_err(err)?;
    tx.execute("DELETE FROM tokens WHERE user_id = ?1", [uid]).map_err(err)?;
    tx.execute("DELETE FROM users WHERE id = ?1", [uid]).map_err(err)?;
    tx.commit().map_err(err)?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
struct Since {
    #[serde(default)]
    since: i64,
}

async fn pull(State(db): State<Db>, headers: HeaderMap, Query(q): Query<Since>) -> ApiResult<Json<Changes>> {
    let conn = db.lock().unwrap();
    let uid = user_from(&headers, &conn)?;
    let mut stmt = conn
        .prepare("SELECT id, kind, ciphertext, nonce, deleted, seq FROM items WHERE user_id = ?1 AND seq > ?2 ORDER BY seq")
        .map_err(err)?;
    let items = stmt
        .query_map(params![uid, q.since], |r| {
            Ok(Item { id: r.get(0)?, kind: r.get(1)?, ciphertext: r.get(2)?, nonce: r.get(3)?, deleted: r.get(4)?, seq: r.get(5)? })
        })
        .map_err(err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(err)?;
    let cursor = items.last().map_or(q.since, |i| i.seq);
    Ok(Json(Changes { items, cursor }))
}

/// Last writer wins per item; each write gets the user's next sequence number.
async fn push(State(db): State<Db>, headers: HeaderMap, Json(items): Json<Vec<Item>>) -> ApiResult<Json<Changes>> {
    let mut conn = db.lock().unwrap();
    let uid = user_from(&headers, &conn)?;
    let tx = conn.transaction().map_err(err)?;
    let mut out = Vec::with_capacity(items.len());
    for mut it in items {
        let seq: i64 = tx
            .query_row("UPDATE users SET seq = seq + 1 WHERE id = ?1 RETURNING seq", [uid], |r| r.get(0))
            .map_err(err)?;
        tx.execute(
            "INSERT INTO items VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT (user_id, id) DO UPDATE SET kind = excluded.kind, ciphertext = excluded.ciphertext,
               nonce = excluded.nonce, deleted = excluded.deleted, seq = excluded.seq",
            params![uid, it.id, it.kind, it.ciphertext, it.nonce, it.deleted, seq],
        )
        .map_err(err)?;
        it.seq = seq;
        out.push(it);
    }
    tx.commit().map_err(err)?;
    let cursor = out.last().map_or(0, |i| i.seq);
    Ok(Json(Changes { items: out, cursor }))
}
