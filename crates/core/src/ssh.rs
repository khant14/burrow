use std::sync::Arc;

use anyhow::{bail, Context, Result};
use russh::client::{self, Handle};
use russh::keys::{decode_secret_key, load_secret_key, PrivateKeyWithHashAlg};
use russh::{ChannelMsg, Disconnect};
use serde::Deserialize;
use tokio::sync::mpsc;

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Auth {
    Password { password: String },
    Key { path: String, passphrase: Option<String> },
    /// Key contents (OpenSSH or PEM), for platforms where apps can't read ~/.ssh.
    KeyData { pem: String, passphrase: Option<String> },
}

#[derive(Debug, Clone, Deserialize)]
pub struct ConnectOptions {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth: Auth,
    pub cols: u32,
    pub rows: u32,
}

/// Input sent from the UI to a running shell.
pub enum Input {
    Data(Vec<u8>),
    Resize { cols: u32, rows: u32 },
    Close,
}

struct Client;

impl client::Handler for Client {
    type Error = russh::Error;

    // TODO(M2): verify against the vault's known_hosts instead of trusting every key.
    async fn check_server_key(
        &mut self,
        _key: &russh::keys::PublicKeyOrCertificate,
    ) -> Result<bool, Self::Error> {
        Ok(true)
    }
}

/// A live interactive shell. Dropping it closes the session.
pub struct Session {
    input: mpsc::UnboundedSender<Input>,
}

impl Session {
    /// Connects, opens a PTY shell and calls `on_output` with every chunk the server sends.
    /// `on_output(None)` is called once when the shell ends.
    pub async fn connect<F>(opts: ConnectOptions, mut on_output: F) -> Result<Self>
    where
        F: FnMut(Option<Vec<u8>>) + Send + 'static,
    {
        let config = Arc::new(client::Config::default());
        let mut handle: Handle<Client> =
            client::connect(config, (opts.host.as_str(), opts.port), Client)
                .await
                .context("connect failed")?;

        let ok = match &opts.auth {
            Auth::Password { password } => handle
                .authenticate_password(&opts.username, password)
                .await?
                .success(),
            Auth::Key { .. } | Auth::KeyData { .. } => {
                let key = match &opts.auth {
                    Auth::Key { path, passphrase } => load_secret_key(path, passphrase.as_deref()),
                    Auth::KeyData { pem, passphrase } => decode_secret_key(pem, passphrase.as_deref()),
                    Auth::Password { .. } => unreachable!(),
                }
                .context("could not load private key")?;
                let hash = handle.best_supported_rsa_hash().await?.flatten();
                handle
                    .authenticate_publickey(
                        &opts.username,
                        PrivateKeyWithHashAlg::new(Arc::new(key), hash),
                    )
                    .await?
                    .success()
            }
        };
        if !ok {
            bail!("authentication failed");
        }

        let mut channel = handle.channel_open_session().await?;
        channel
            .request_pty(false, "xterm-256color", opts.cols, opts.rows, 0, 0, &[])
            .await?;
        channel.request_shell(false).await?;

        let (tx, mut rx) = mpsc::unbounded_channel::<Input>();
        tokio::spawn(async move {
            loop {
                tokio::select! {
                    msg = channel.wait() => match msg {
                        Some(ChannelMsg::Data { data }) => on_output(Some(data.to_vec())),
                        Some(ChannelMsg::ExtendedData { data, .. }) => on_output(Some(data.to_vec())),
                        Some(ChannelMsg::ExitStatus { .. }) | None => break,
                        _ => {}
                    },
                    input = rx.recv() => match input {
                        Some(Input::Data(d)) => { let _ = channel.data(&d[..]).await; }
                        Some(Input::Resize { cols, rows }) => {
                            let _ = channel.window_change(cols, rows, 0, 0).await;
                        }
                        Some(Input::Close) | None => break,
                    },
                }
            }
            let _ = handle.disconnect(Disconnect::ByApplication, "", "en").await;
            on_output(None);
        });

        Ok(Self { input: tx })
    }

    pub fn write(&self, data: Vec<u8>) {
        let _ = self.input.send(Input::Data(data));
    }

    pub fn resize(&self, cols: u32, rows: u32) {
        let _ = self.input.send(Input::Resize { cols, rows });
    }

    pub fn close(&self) {
        let _ = self.input.send(Input::Close);
    }
}
