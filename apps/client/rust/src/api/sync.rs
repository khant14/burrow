//! Dart-facing sync API. Thin wrapper over `burrow_core::sync`.
use burrow_core::sync as core;

pub struct SyncAccount {
    pub server: String,
    pub email: String,
    pub token: String,
    pub vault_key: String,
}

pub struct SyncItem {
    pub id: String,
    pub kind: String,
    pub data: String,
    pub updated_at: i64,
    pub deleted: bool,
    pub dirty: bool,
}

pub struct SyncRound {
    pub apply: Vec<SyncItem>,
    pub pushed: Vec<String>,
    pub cursor: i64,
}

fn to_dart(a: core::Account) -> SyncAccount {
    SyncAccount { server: a.server, email: a.email, token: a.token, vault_key: a.vault_key }
}

fn e(e: anyhow::Error) -> String {
    format!("{e:#}")
}

pub async fn sync_register(server: String, email: String, password: String) -> Result<SyncAccount, String> {
    core::register(&server, &email, &password).await.map(to_dart).map_err(e)
}

pub async fn sync_login(server: String, email: String, password: String) -> Result<SyncAccount, String> {
    core::login(&server, &email, &password).await.map(to_dart).map_err(e)
}

pub async fn sync_delete_account(server: String, token: String) -> Result<(), String> {
    core::delete_account(&server, &token).await.map_err(e)
}

pub async fn sync_round(account: SyncAccount, cursor: i64, local: Vec<SyncItem>) -> Result<SyncRound, String> {
    let acct = core::Account { server: account.server, email: account.email, token: account.token, vault_key: account.vault_key };
    let local = local
        .into_iter()
        .map(|l| core::LocalItem { id: l.id, kind: l.kind, data: l.data, updated_at: l.updated_at, deleted: l.deleted, dirty: l.dirty })
        .collect();
    let r = core::sync_round(&acct, cursor, local).await.map_err(e)?;
    Ok(SyncRound {
        apply: r
            .apply
            .into_iter()
            .map(|l| SyncItem { id: l.id, kind: l.kind, data: l.data, updated_at: l.updated_at, deleted: l.deleted, dirty: l.dirty })
            .collect(),
        pushed: r.pushed,
        cursor: r.cursor,
    })
}
