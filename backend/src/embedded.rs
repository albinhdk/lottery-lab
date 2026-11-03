//! In-process server used by the Android app.
//!
//! The Flutter side loads `liblottery_lab_backend.so`, calls
//! [`lottery_lab_start`] with the path of its on-device SQLite file, and
//! receives the loopback port the HTTP API is listening on. Everything the
//! desktop server does (analysis, backtest, sync, import) then runs inside
//! the app process, so the phone no longer needs a PC backend.

use std::ffi::{CStr, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::mpsc;
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use anyhow::{Context, Result};

use crate::{build_router, db::Db, spawn_auto_sync};

static PORT: OnceLock<u16> = OnceLock::new();

/// Starts the embedded HTTP server once and returns its loopback port.
/// Returns `-1` on failure. The returned port stays valid for the lifetime
/// of the process.
#[unsafe(no_mangle)]
pub extern "C" fn lottery_lab_start(db_path: *const c_char) -> i32 {
    catch_unwind(AssertUnwindSafe(|| start_checked(db_path))).unwrap_or_else(|_| {
        eprintln!("lottery_lab_start: panic while starting the embedded server");
        -1
    })
}

fn start_checked(db_path: *const c_char) -> i32 {
    if let Some(port) = PORT.get() {
        return i32::from(*port);
    }
    if db_path.is_null() {
        eprintln!("lottery_lab_start: null database path");
        return -1;
    }
    let path = match unsafe { CStr::from_ptr(db_path) }.to_str() {
        Ok(value) => value.to_owned(),
        Err(_) => {
            eprintln!("lottery_lab_start: database path is not valid UTF-8");
            return -1;
        }
    };
    match start(&path) {
        Ok(port) => {
            let _ = PORT.set(port);
            i32::from(port)
        }
        Err(err) => {
            eprintln!("lottery_lab_start: {err:#}");
            -1
        }
    }
}

fn start(db_path: &str) -> Result<u16> {
    let db = Arc::new(Db::open(db_path)?);
    let (tx, rx) = mpsc::sync_channel(1);

    std::thread::Builder::new()
        .name("lottery-lab-server".into())
        .spawn(move || {
            let runtime = match tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
            {
                Ok(runtime) => runtime,
                Err(err) => {
                    eprintln!("lottery_lab_start: build tokio runtime: {err}");
                    return;
                }
            };
            runtime.block_on(async move {
                let app = build_router(db.clone());
                let listener = match tokio::net::TcpListener::bind("127.0.0.1:0").await {
                    Ok(listener) => listener,
                    Err(err) => {
                        eprintln!("lottery_lab_start: bind loopback: {err}");
                        return;
                    }
                };
                let port = match listener.local_addr() {
                    Ok(addr) => addr.port(),
                    Err(err) => {
                        eprintln!("lottery_lab_start: read local addr: {err}");
                        return;
                    }
                };
                if tx.send(port).is_err() {
                    return;
                }
                spawn_auto_sync(db);
                if let Err(err) = axum::serve(listener, app).await {
                    eprintln!("lottery_lab_start: server stopped: {err}");
                }
            });
        })
        .context("spawn embedded server thread")?;

    rx.recv_timeout(Duration::from_secs(5))
        .context("embedded server did not report a port in time")
}
