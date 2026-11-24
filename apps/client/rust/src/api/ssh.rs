//! Dart-facing API. Thin wrapper over burrow-core; keep logic in the core crate.
use std::sync::Mutex;

use burrow_core::{Auth, ConnectOptions, Session};
use flutter_rust_bridge::frb;
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver};

use crate::frb_generated::StreamSink;

pub struct SshTarget {
    pub host: String,
    pub port: u16,
    pub username: String,
    /// Used when `key_path` is empty.
    pub password: Option<String>,
    pub key_path: Option<String>,
    pub key_passphrase: Option<String>,
}

/// A live shell. Opaque on the Dart side.
#[frb(opaque)]
pub struct SshSession {
    inner: Session,
    output: Mutex<Option<UnboundedReceiver<Vec<u8>>>>,
}

impl SshSession {
    /// Connects and opens a shell. Call `output()` once to receive terminal bytes.
    pub async fn connect(target: SshTarget, cols: u32, rows: u32) -> Result<SshSession, String> {
        let auth = match target.key_path.filter(|p| !p.is_empty()) {
            Some(path) => Auth::Key { path, passphrase: target.key_passphrase },
            None => Auth::Password { password: target.password.unwrap_or_default() },
        };
        let opts = ConnectOptions { host: target.host, port: target.port, username: target.username, auth, cols, rows };
        // Buffer output until Dart subscribes, so the login banner isn't lost.
        let (tx, rx) = unbounded_channel();
        let mut tx = Some(tx);
        let inner = Session::connect(opts, move |chunk| match chunk {
            Some(data) => {
                if let Some(tx) = &tx {
                    let _ = tx.send(data);
                }
            }
            None => drop(tx.take()),
        })
        .await
        .map_err(|e| format!("{e:#}"))?;
        Ok(SshSession { inner, output: Mutex::new(Some(rx)) })
    }

    /// Terminal output. The stream ends when the shell exits.
    pub async fn output(&self, sink: StreamSink<Vec<u8>>) {
        let Some(mut rx) = self.output.lock().unwrap().take() else { return };
        while let Some(data) = rx.recv().await {
            if sink.add(data).is_err() {
                break;
            }
        }
    }

    #[frb(sync)]
    pub fn write(&self, data: Vec<u8>) {
        self.inner.write(data);
    }

    #[frb(sync)]
    pub fn resize(&self, cols: u32, rows: u32) {
        self.inner.resize(cols, rows);
    }

    #[frb(sync)]
    pub fn close(&self) {
        self.inner.close();
    }
}

#[frb(init)]
pub fn init_app() {
    // Never capture backtraces in-process: walking the stack through the Flutter
    // engine's frames segfaults (seen on Linux), which turned every connection
    // error into a crash. Errors cross the bridge as plain strings instead.
    std::env::set_var("RUST_BACKTRACE", "0");
    std::env::set_var("RUST_LIB_BACKTRACE", "0");
}

