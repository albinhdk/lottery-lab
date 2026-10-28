mod analysis;
mod backtest;
mod config;
mod db;
mod models;
mod routes;
mod sources;
mod stats;
mod strategies;

use std::net::SocketAddr;
use std::path::Path;
use std::sync::Arc;

use anyhow::Result;
use axum::Router;
use tower_http::{
    cors::CorsLayer,
    services::{ServeDir, ServeFile},
    trace::TraceLayer,
};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "lottery_lab_backend=info,tower_http=warn".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let db_path = std::env::var("LOTTERY_DB").unwrap_or_else(|_| "data/lottery.db".into());
    let db = Arc::new(db::Db::open(&db_path)?);
    tracing::info!("database: {db_path}");

    let state = routes::AppState { db: db.clone() };
    let app = routes::router(state)
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http());

    let web_dir =
        std::env::var("LOTTERY_WEB_DIR").unwrap_or_else(|_| "../frontend/build/web".into());
    let index = Path::new(&web_dir).join("index.html");
    let app: Router = if index.exists() {
        tracing::info!("serving web build from {web_dir}");
        app.fallback_service(
            ServeDir::new(&web_dir).fallback(ServeFile::new(index.to_string_lossy().to_string())),
        )
    } else {
        app
    };

    spawn_auto_sync(db.clone());

    let addr: SocketAddr = std::env::var("LOTTERY_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:8787".into())
        .parse()?;
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!("Lottery Lab backend listening on http://{addr}");
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

fn spawn_auto_sync(db: Arc<db::Db>) {
    tokio::spawn(async move {
        for g in config::GAMES {
            let existing = db.count(g.id).unwrap_or(0);
            if existing > 0 {
                continue;
            }
            tracing::info!("首次启动，自动同步 {} 历史数据…", g.name);
            match sources::sync(g.id, true, &g).await {
                Ok(draws) => match db.upsert_many(&draws, "official") {
                    Ok(written) => tracing::info!("{} 同步完成：{} 条写入", g.name, written),
                    Err(e) => tracing::warn!("{} 写入失败: {e:#}", g.name),
                },
                Err(e) => tracing::warn!("{} 同步失败（可稍后手动同步）: {e:#}", g.name),
            }
        }
    });
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
    tracing::info!("shutting down");
}
