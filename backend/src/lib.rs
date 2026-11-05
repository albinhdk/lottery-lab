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

use chrono::{DateTime, FixedOffset, Timelike};
use std::sync::Arc;
use std::time::Duration;

use axum::Router;
use tower_http::cors::CorsLayer;

use crate::db::Db;

/// How often the background task checks the official feeds while no draw is
/// expected. A draw only lands a few times a week, so polling hard around the
/// clock would just hammer the official sites.
/// Override with `LOTTERY_SYNC_INTERVAL_SECS` (minimum 60 seconds).
const DEFAULT_SYNC_INTERVAL_SECS: u64 = 600;

/// Both games draw in the evening and the official feeds publish the numbers
/// within minutes, so this window is polled much harder — it is the only time
/// anyone is waiting for a result.
const DRAW_WINDOW_START_HOUR: u32 = 20;
const DRAW_WINDOW_END_HOUR: u32 = 24;
const DRAW_WINDOW_INTERVAL_SECS: u64 = 120;

/// Draws happen in Beijing time, so the window is evaluated there. A fixed
/// offset keeps this right wherever the server runs and needs no timezone
/// database — the embedded Android backend has no Context for one.
const CN_OFFSET_SECS: i32 = 8 * 3600;

/// The API router shared by the standalone server and the embedded
/// (mobile) server. CORS is permissive so the Web build can call it from
/// any origin.
pub fn build_router(db: Arc<Db>) -> Router {
    routes::router(routes::AppState { db }).layer(CorsLayer::permissive())
}

fn env_override() -> Option<u64> {
    std::env::var("LOTTERY_SYNC_INTERVAL_SECS")
        .ok()
        .and_then(|v| v.trim().parse::<u64>().ok())
        .filter(|&v| v >= 60)
}

/// Current Beijing wall-clock time.
fn now_cn() -> DateTime<FixedOffset> {
    let offset = FixedOffset::east_opt(CN_OFFSET_SECS).expect("valid Beijing offset");
    chrono::Utc::now().with_timezone(&offset)
}

/// True while the evening draw window is open.
fn in_draw_window(now: DateTime<FixedOffset>) -> bool {
    let hour = now.hour();
    hour >= DRAW_WINDOW_START_HOUR && hour < DRAW_WINDOW_END_HOUR
}

fn interval_for(now: DateTime<FixedOffset>) -> Duration {
    if in_draw_window(now) {
        Duration::from_secs(DRAW_WINDOW_INTERVAL_SECS)
    } else {
        Duration::from_secs(DEFAULT_SYNC_INTERVAL_SECS)
    }
}

/// How long to wait before the next poll. An explicit environment override
/// always wins; otherwise the cadence follows the draw window. Re-evaluated on
/// every cycle, so entering the window takes effect on the next tick — which
/// still lands well before the ~21:15 draw.
fn sync_interval() -> Duration {
    match env_override() {
        Some(secs) => Duration::from_secs(secs),
        None => interval_for(now_cn()),
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{NaiveDate, TimeZone};

    /// A wall-clock time in Beijing, however the host machine is zoned.
    fn beijing(hour: u32, minute: u32) -> DateTime<FixedOffset> {
        let offset = FixedOffset::east_opt(CN_OFFSET_SECS).unwrap();
        let naive = NaiveDate::from_ymd_opt(2026, 11, 5)
            .unwrap()
            .and_hms_opt(hour, minute, 0)
            .unwrap();
        offset.from_local_datetime(&naive).unwrap()
    }

    #[test]
    fn draw_window_covers_the_evening_draws() {
        assert!(in_draw_window(beijing(20, 0)));
        assert!(in_draw_window(beijing(21, 15)));
        assert!(in_draw_window(beijing(23, 59)));
        assert!(!in_draw_window(beijing(19, 59)));
        assert!(!in_draw_window(beijing(0, 30)));
        assert!(!in_draw_window(beijing(9, 0)));
    }

    #[test]
    fn window_polls_faster_than_the_idle_cadence() {
        assert_eq!(interval_for(beijing(21, 15)), Duration::from_secs(120));
        assert_eq!(interval_for(beijing(3, 0)), Duration::from_secs(600));
    }

    #[test]
    fn the_window_follows_beijing_time_not_the_host_clock() {
        // 12:00 UTC is 20:00 in Beijing, whatever the host's own zone says.
        let noon_utc = chrono::Utc
            .with_ymd_and_hms(2026, 11, 5, 12, 0, 0)
            .unwrap();
        let as_beijing = noon_utc.with_timezone(&FixedOffset::east_opt(CN_OFFSET_SECS).unwrap());
        assert_eq!(as_beijing.hour(), 20);
        assert!(in_draw_window(as_beijing));
    }
}
