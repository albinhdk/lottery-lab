pub mod analysis;
pub mod bets;
pub mod backtest;
pub mod config;
pub mod db;
pub mod embedded;
pub mod models;
pub mod prize;
pub mod routes;
pub mod sources;
pub mod stats;
pub mod strategies;

use std::sync::Arc;
use std::time::Duration;

use axum::Router;
use tower_http::cors::CorsLayer;

use crate::db::Db;

/// How often the background task checks the official feeds for new draws.
/// Override with `LOTTERY_SYNC_INTERVAL_SECS` (minimum 60 seconds).
const DEFAULT_SYNC_INTERVAL_SECS: u64 = 600;

/// The API router shared by the standalone server and the embedded
/// (mobile) server. CORS is permissive so the Web build can call it from
/// any origin.
pub fn build_router(db: Arc<Db>) -> Router {
    routes::router(routes::AppState { db }).layer(CorsLayer::permissive())
}

fn sync_interval() -> Duration {
    let secs = std::env::var("LOTTERY_SYNC_INTERVAL_SECS")
        .ok()
        .and_then(|v| v.trim().parse::<u64>().ok())
        .filter(|&v| v >= 60)
        .unwrap_or(DEFAULT_SYNC_INTERVAL_SECS);
    Duration::from_secs(secs)
}

/// Keep the database fresh: an empty database is filled with the full
/// history, otherwise only the newest official page is polled. Runs once at
/// startup and then forever on an interval, so a draw that happened while
/// the app was closed shows up without pressing "同步数据".
pub fn spawn_auto_sync(db: Arc<Db>) {
    tokio::spawn(async move {
        loop {
            sync_once(&db).await;
            tokio::time::sleep(sync_interval()).await;
        }
    });
}

async fn sync_once(db: &Db) {
    for g in config::GAMES {
        let empty = db.count(g.id).unwrap_or(0) == 0;
        let before = db.latest(g.id).ok().flatten().map(|d| d.issue);
        let fetched = if empty {
            tracing::info!("数据库为空，开始全量同步 {} 历史数据…", g.name);
            sources::sync(g.id, true, &g).await
        } else {
            sources::fetch_recent(g.id).await
        };
        match fetched {
            Ok(draws) => match db.upsert_many(&draws, "official") {
                Ok(_) => {
                    let after = db.latest(g.id).ok().flatten();
                    let changed = after.as_ref().map(|d| d.issue.clone()) != before;
                    if empty || changed {
                        match after {
                            Some(d) => tracing::info!(
                                "{} 数据已更新至 {} 期（{}）",
                                g.name,
                                d.issue,
                                d.date
                            ),
                            None => tracing::warn!("{} 同步成功但没有返回数据", g.name),
                        }
                    }
                    // A newly drawn issue settles the bets waiting on it. This
                    // is the automatic prize check: purely local, no extra
                    // network call, and `draws` is never modified.
                    check_bets(db, g.id);
                }
                Err(e) => tracing::warn!("{} 写入失败: {e:#}", g.name),
            },
            Err(e) => tracing::warn!("{} 同步失败（稍后自动重试）: {e:#}", g.name),
        }
    }
}

/// Settles pending bets for one game against the issues already stored.
/// Failures are logged and never abort the sync loop.
fn check_bets(db: &Db, game: &str) {
    let cache: Vec<crate::models::Draw> = db.recent(game, 400).unwrap_or_default();
    let lookup = move |game_id: &str, issue: &str| {
        cache
            .iter()
            .find(|d| d.game == game_id && d.issue == issue)
            .cloned()
    };
    match db.check_pending_bets(lookup) {
        Ok(outcome) => {
            if outcome.settled > 0 {
                tracing::info!(
                    "{} 自动对奖完成：结算 {} 注，其中中奖 {} 注，待开奖 {} 注",
                    config::game(game).map(|g| g.name).unwrap_or(game),
                    outcome.settled,
                    outcome.won,
                    outcome.still_pending
                );
            }
        }
        Err(e) => tracing::warn!("{game} 自动对奖失败: {e:#}"),
    }
}
