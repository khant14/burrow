# Burrow SSH: architecture plan (draft)

Open source, self-hostable SSH client in the spirit of Termius: a fast terminal, a host vault, and optional end-to-end-encrypted sync across devices through a server you run yourself.

## Goals
- One codebase for iOS, Android, macOS, Windows and Linux, with a native feel on each.
- Hosts, groups, identities (keys/passwords), snippets, port forwards, known_hosts.
- SSH: password, keys (ed25519/RSA/ECDSA), agent, jump hosts (ProxyJump), local/remote/dynamic forwarding, SFTP browser.
- Works fully offline with no account. Sync is opt-in.
- Sync server never sees plaintext (zero-knowledge).

## Stack (decided)
| Part | Choice | Why |
|---|---|---|
| App | **Flutter** (Dart, Material 3 + adaptive/Cupertino widgets) | One UI codebase compiled to native code on all five platforms; renders at 60-120 fps, platform-specific scrolling, transitions and controls |
| Terminal UI | **xterm.dart** | Native Flutter terminal emulator (no WebView) |
| Rust bridge | **flutter_rust_bridge 2** + cargokit | Generates Dart bindings and builds the Rust crate for each platform automatically |
| SSH engine | **russh** + russh-sftp (Rust) | Pure Rust, async, forwarding, agent, jump hosts; no OpenSSH dependency, works on iOS |
| Local vault | SQLite (rusqlite) in Rust, secrets encrypted with a master key; OS keychain/Keystore via flutter_secure_storage | Offline-first |
| Sync server | **Rust** (Axum + SQLite, Postgres later), single binary + Docker image | One language for all logic; shares wire types and crypto with the app |
| Crypto | Argon2id (KDF), XChaCha20-Poly1305, X25519 for sharing (RustCrypto crates) | Well-reviewed, one implementation shared by client and server |

Considered and dropped: Tauri + React (WebView UI, weaker mobile story), Electron (size), a Go server (second language).

## Components
```
apps/client         Flutter app (lib/ = Dart UI)
apps/client/rust    Bridge crate: thin Dart-facing API over crates/core
crates/core         SSH sessions, forwarding, SFTP, vault, sync client (Rust)
crates/proto        Wire types shared by app and server
server              Sync server (Rust, Axum): auth, encrypted blob store, change feed
```

Data flow: xterm.dart <-> Dart `SshSession` (generated) <-> flutter_rust_bridge <-> burrow-core <-> russh <-> remote host. Terminal output is a Dart `Stream<Uint8List>` fed from Rust; keystrokes go back as sync calls.

Rule: all logic (SSH, vault, crypto, sync) lives in Rust crates; Dart only does UI and state.

## End-to-end encrypted sync
1. User picks a master password. Client derives `KEK = Argon2id(password, salt)`.
2. A random 256-bit **vault key** encrypts every item; vault key is stored on the server wrapped by the KEK.
3. Login uses a separate derived auth key (or OPAQUE later) so the server never learns the password.
4. Each item (host, key, snippet) is an encrypted blob `{id, kind, ciphertext, nonce, deleted, seq}`. Server stores and orders blobs only; metadata leak is limited to counts, kinds and timestamps.
5. Sync: pull changes since cursor, push local changes, last-writer-wins per item (version vectors later). Tombstones for deletes.
6. Team sharing (later): per-vault keys wrapped to each member's X25519 public key.
7. Recovery key printed at signup; losing both password and recovery key means data loss (by design).

## Server API
- `POST /v1/auth/register`, `POST /v1/auth/login` (returns bearer token)
- `GET|PUT /v1/vault/key` (wrapped vault key)
- `GET /v1/items?since=<cursor>`, `PUT /v1/items` (batch); WebSocket `/v1/events` for live updates (later)
- Deploy: Docker image from `server/Dockerfile`; env `BURROW_DB`, `BURROW_ADDR`; TLS via reverse proxy.

## Platform notes
- iOS/Android: background SSH sessions are limited by the OS; keep-alive via foreground service on Android, reconnect on resume on iOS.
- Mobile needs an extra-keys bar (Esc, Ctrl, Tab, arrows) above the keyboard.
- Web (later): Flutter web works, but browsers cannot open raw TCP, so it needs a self-hosted WebSocket-to-SSH gateway.

## Milestones
1. **M0** Monorepo scaffold, CI, license. (done: scaffold)
2. **M1** Connect with password/key, tabs, host list, mobile extra-keys bar.
3. **M2** Vault encryption, keychain, snippets, known_hosts verification, jump hosts.
4. **M3** Port forwarding, SFTP panel.
5. **M4** E2EE sync against burrow-server.
6. **M5** Web gateway, team sharing.

## Prior art to study
Tabby, Electerm, WindTerm, Warpgate (Rust SSH bastion), Bitwarden/Vaultwarden (E2EE sync model), xterm.dart's example SSH app.

## Open decisions
- License: MIT vs Apache-2.0 vs AGPL for the server.
