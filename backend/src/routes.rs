use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::{
    analysis, backtest,
    bets::{BetInput, BetStatus},
    config, db::Db, models::Draw, prize, sources,
    strategies::{StrategyKind, StrategyRunner},
};

#[derive(Clone)]
pub struct AppState {
    pub db: Arc<Db>,
}

#[derive(Debug)]
pub struct AppError {
    pub status: StatusCode,
    pub message: String,
}

impl AppError {
    pub fn bad(msg: impl Into<String>) -> Self {
        Self {
            status: StatusCode::BAD_REQUEST,
            message: msg.into(),
        }
    }

    pub fn not_found(msg: impl Into<String>) -> Self {
        Self {
            status: StatusCode::NOT_FOUND,
            message: msg.into(),
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        (
            self.status,
            Json(json!({ "error": self.message })),
        )
            .into_response()
    }
}

impl<E> From<E> for AppError
where
    E: Into<anyhow::Error>,
{
    fn from(err: E) -> Self {
        Self {
            status: StatusCode::INTERNAL_SERVER_ERROR,
            message: format!("{:#}", err.into()),
        }
    }
}

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/api/health", get(health))
        .route("/api/games", get(games))
        .route("/api/draws", get(draws))
        .route("/api/draws/export", get(export_draws))
        .route("/api/draws/{game}/{issue}", get(get_draw))
        .route("/api/stats/frequency", get(frequency))
        .route("/api/stats/gaps", get(gaps))
        .route("/api/stats/combinations", get(combinations))
        .route("/api/stats/randomness", get(randomness))
        .route("/api/strategies", get(strategy_list))
        .route("/api/tickets", post(tickets))
        .route("/api/prize-check", post(prize_check))
        .route("/api/bets", get(list_bets).post(create_bets))
        .route("/api/bets/summary", get(bets_summary))
        .route("/api/bets/check", post(check_bets))
        .route("/api/bets/{id}", axum::routing::delete(delete_bet))
        .route(
            "/api/bets/{id}/actual-amount",
            axum::routing::patch(set_actual_amount),
        )
        .route("/api/backtest", post(run_backtest))
        .route("/api/sync", post(sync))
        .route("/api/import", post(import))
        .with_state(state)
}

fn game_or_err(id: &str) -> Result<&'static config::GameDef, AppError> {
    config::game(id).ok_or_else(|| AppError::bad(format!("未知彩种: {id}")))
}

fn draws_or_err(state: &AppState, game: &str) -> Result<Vec<Draw>, AppError> {
    let draws = state.db.all_asc(game)?;
    if draws.is_empty() {
        return Err(AppError::bad("该彩种暂无历史数据，请先同步"));
    }
    Ok(draws)
}

async fn health() -> Json<Value> {
    Json(json!({
        "status": "ok",
        "service": "lottery-lab",
        "version": env!("CARGO_PKG_VERSION"),
    }))
}

async fn games(State(state): State<AppState>) -> Result<Json<Value>, AppError> {
    let mut out = Vec::new();
    for g in config::GAMES {
        let count = state.db.count(g.id)?;
        let latest = state.db.latest(g.id)?;
        let range = state.db.date_range(g.id)?;
        out.push(json!({
            "id": g.id,
            "name": g.name,
            "primary_label": g.primary_label,
            "primary_count": g.primary_count,
            "primary_max": g.primary_max,
            "secondary_label": g.secondary_label,
            "secondary_count": g.secondary_count,
            "secondary_max": g.secondary_max,
            "price": g.price,
            "prize_note": g.prize_note,
            "count": count,
            "latest": latest,
            "first_date": range.as_ref().map(|r| r.0.clone()),
            "last_date": range.as_ref().map(|r| r.1.clone()),
            // Suggested issue for a new bet, derived from the numbering scheme.
            "next_issue": state.db.next_issue(g.id)?,
        }));
    }
    Ok(Json(json!({ "games": out })))
}

#[derive(Deserialize)]
struct DrawsQuery {
    game: String,
    #[serde(default)]
    page: Option<usize>,
    #[serde(default)]
    page_size: Option<usize>,
    #[serde(default)]
    q: Option<String>,
    #[serde(default)]
    from: Option<String>,
    #[serde(default)]
    to: Option<String>,
}

async fn draws(
    State(state): State<AppState>,
    Query(q): Query<DrawsQuery>,
) -> Result<Json<Value>, AppError> {
    game_or_err(&q.game)?;
    let page = state.db.page(
        &q.game,
        q.page.unwrap_or(1),
        q.page_size.unwrap_or(50),
        q.q.as_deref(),
        q.from.as_deref(),
        q.to.as_deref(),
    )?;
    Ok(Json(serde_json::to_value(page)?))
}

async fn get_draw(
    State(state): State<AppState>,
    Path((game, issue)): Path<(String, String)>,
) -> Result<Json<Value>, AppError> {
    game_or_err(&game)?;
    match state.db.get(&game, &issue)? {
        Some(d) => Ok(Json(serde_json::to_value(d)?)),
        None => Err(AppError::not_found(format!("未找到 {game} 期号 {issue}"))),
    }
}

async fn export_draws(
    State(state): State<AppState>,
    Query(q): Query<DrawsQuery>,
) -> Result<Response, AppError> {
    game_or_err(&q.game)?;
    let draws = state.db.all_asc(&q.game)?;
    let mut csv = String::from("issue,date,primary,secondary\n");
    for d in draws {
        let primary = d
            .primary
            .iter()
            .map(|n| n.to_string())
            .collect::<Vec<_>>()
            .join(" ");
        let secondary = d
            .secondary
            .iter()
            .map(|n| n.to_string())
            .collect::<Vec<_>>()
            .join(" ");
        csv.push_str(&format!(
            "{},{},{},{}\n",
            d.issue, d.date, primary, secondary
        ));
    }
    Ok((
        [
            (header::CONTENT_TYPE, "text/csv; charset=utf-8"),
            (
                header::CONTENT_DISPOSITION,
                "attachment; filename=\"lottery-history.csv\"",
            ),
        ],
        csv,
    )
        .into_response())
}

#[derive(Deserialize)]
struct StatsQuery {
    game: String,
    #[serde(default)]
    window: Option<usize>,
    #[serde(default)]
    simulations: Option<usize>,
}

async fn frequency(
    State(state): State<AppState>,
    Query(q): Query<StatsQuery>,
) -> Result<Json<Value>, AppError> {
    let g = game_or_err(&q.game)?;
    let draws = draws_or_err(&state, &q.game)?;
    let window = q.window.filter(|&w| w > 0);
    Ok(Json(analysis::frequency(&draws, g, window)))
}

async fn gaps(
    State(state): State<AppState>,
    Query(q): Query<StatsQuery>,
) -> Result<Json<Value>, AppError> {
    let g = game_or_err(&q.game)?;
    let draws = draws_or_err(&state, &q.game)?;
    Ok(Json(analysis::gaps(&draws, g)))
}

async fn combinations(
    State(state): State<AppState>,
    Query(q): Query<StatsQuery>,
) -> Result<Json<Value>, AppError> {
    let g = game_or_err(&q.game)?;
    let draws = draws_or_err(&state, &q.game)?;
    if draws.len() < 30 {
        return Err(AppError::bad("至少需要 30 期数据才能做组合特征分析"));
    }
    Ok(Json(analysis::combinations(&draws, g)))
}

async fn randomness(
    State(state): State<AppState>,
    Query(q): Query<StatsQuery>,
) -> Result<Json<Value>, AppError> {
    let g = game_or_err(&q.game)?;
    let draws = draws_or_err(&state, &q.game)?;
    if draws.len() < 60 {
        return Err(AppError::bad("至少需要 60 期数据才能做随机性检验"));
    }
    Ok(Json(analysis::randomness(
        &draws,
        g,
        q.simulations.unwrap_or(300),
        q.window.filter(|&w| w > 0),
    )))
}

async fn strategy_list() -> Json<Value> {
    let items: Vec<Value> = StrategyKind::all()
        .iter()
        .map(|k| {
            json!({
                "id": k.id(),
                "label": k.label(),
                "description": k.description(),
            })
        })
        .collect();
    Json(json!({ "strategies": items }))
}

#[derive(Deserialize)]
struct TicketRequest {
    game: String,
    strategy: String,
    #[serde(default)]
    count: Option<usize>,
    #[serde(default)]
    seed: Option<u64>,
}

async fn tickets(
    State(state): State<AppState>,
    Json(req): Json<TicketRequest>,
) -> Result<Json<Value>, AppError> {
    let g = game_or_err(&req.game)?;
    let draws = draws_or_err(&state, &req.game)?;
    if draws.len() < 30 {
        return Err(AppError::bad("至少需要 30 期数据才能生成号码"));
    }
    let kind = StrategyKind::from_id(&req.strategy)
        .ok_or_else(|| AppError::bad(format!("未知策略: {}", req.strategy)))?;
    let count = req.count.unwrap_or(5).clamp(1, 20);
    let mut runner = StrategyRunner::new(kind, *g, &draws, req.seed.unwrap_or(2026));
    let mut list = Vec::with_capacity(count);
    for i in 0..count {
        let p = runner.predict_variant(&draws, i);
        list.push(json!({
            "primary": p.primary,
            "secondary": p.secondary,
        }));
    }
    Ok(Json(json!({
        "game": g.id,
        "game_name": g.name,
        "strategy": kind.id(),
        "strategy_label": kind.label(),
        "description": kind.description(),
        "tickets": list,
        "disclaimer": "号码由所选规则随机生成。任何选号方法都不会改变中奖概率；请理性购彩，量力而行。",
    })))
}

#[derive(Deserialize)]
struct PrizeCheckRequest {
    game: String,
    #[serde(default)]
    issue: Option<String>,
    primary: Vec<u8>,
    secondary: Vec<u8>,
}

/// Checks one hand-picked ticket against a draw. When \`issue\` is omitted the
/// latest draw is used.
async fn prize_check(
    State(state): State<AppState>,
    Json(req): Json<PrizeCheckRequest>,
) -> Result<Json<Value>, AppError> {
    let g = game_or_err(&req.game)?;
    validate_pick(
        &req.primary,
        g.primary_count,
        g.primary_max,
        g.primary_label,
    )?;
    validate_pick(
        &req.secondary,
        g.secondary_count,
        g.secondary_max,
        g.secondary_label,
    )?;

    let issue = req
        .issue
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let draw = match issue {
        Some(issue) => state.db.get(&req.game, issue)?.ok_or_else(|| AppError {
            status: StatusCode::NOT_FOUND,
            message: format!("未找到 {} 期号 {issue}", g.name),
        })?,
        None => state
            .db
            .latest(&req.game)?
            .ok_or_else(|| AppError::bad("该彩种暂无开奖数据，请先同步"))?,
    };

    let mut primary = req.primary;
    primary.sort_unstable();
    let mut secondary = req.secondary;
    secondary.sort_unstable();
    Ok(Json(serde_json::to_value(prize::evaluate(
        &draw,
        g,
        &primary,
        &secondary,
    ))?))
}

fn validate_pick(nums: &[u8], count: usize, max: u8, label: &str) -> Result<(), AppError> {
    if nums.len() != count {
        return Err(AppError::bad(format!(
            "{label}需要选择 {count} 个号码（当前 {} 个）",
            nums.len()
        )));
    }
    if let Some(bad) = nums.iter().find(|&&n| n < 1 || n > max) {
        return Err(AppError::bad(format!("{label}号码 {bad} 超出 1–{max} 范围")));
    }
    if !is_unique(nums) {
        return Err(AppError::bad(format!("{label}号码不能重复")));
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Bets: personal ticket records and automatic prize checking
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct CreateBetsRequest {
    game: String,
    bets: Vec<BetInput>,
}

/// Records one or more tickets. The frontend expands a "追号 N 期" request
/// into N entries before calling this, so each row stays independent and is
/// settled on its own issue.
async fn create_bets(
    State(state): State<AppState>,
    Json(req): Json<CreateBetsRequest>,
) -> Result<Json<Value>, AppError> {
    let g = game_or_err(&req.game)?;
    if req.bets.is_empty() {
        return Err(AppError::bad("没有要保存的号码"));
    }
    if req.bets.len() > 500 {
        return Err(AppError::bad("一次最多保存 500 注"));
    }
    for bet in &req.bets {
        if bet.issue.trim().is_empty() {
            return Err(AppError::bad("期号不能为空"));
        }
        validate_pick(&bet.primary, g.primary_count, g.primary_max, g.primary_label)?;
        validate_pick(
            &bet.secondary,
            g.secondary_count,
            g.secondary_max,
            g.secondary_label,
        )?;
    }

    let outcome = state.db.bets().insert(g.id, &req.bets, g.price)?;
    // A newly saved bet may target an issue that is already drawn (the user
    // is backfilling a ticket bought earlier), so check right away.
    let cache = draw_cache(&state.db, g.id);
    let checked = state.db.check_pending_bets(lookup(&cache))?;
    Ok(Json(json!({
        "game": g.id,
        "game_name": g.name,
        "inserted": outcome.inserted,
        "duplicates": outcome.duplicates,
        "checked": checked,
        "total": state.db.bets().page(None, None, 1, 1)?.total,
    })))
}

#[derive(Deserialize)]
struct BetsQuery {
    #[serde(default)]
    game: Option<String>,
    #[serde(default)]
    status: Option<String>,
    #[serde(default)]
    page: Option<usize>,
    #[serde(default)]
    page_size: Option<usize>,
}

async fn list_bets(
    State(state): State<AppState>,
    Query(q): Query<BetsQuery>,
) -> Result<Json<Value>, AppError> {
    if let Some(g) = q.game.as_deref().filter(|g| !g.trim().is_empty()) {
        game_or_err(g)?;
    }
    let status = match q.status.as_deref() {
        Some("pending") => Some(BetStatus::Pending),
        Some("won") => Some(BetStatus::Won),
        Some("lost") => Some(BetStatus::Lost),
        Some(other) => {
            return Err(AppError::bad(format!("未知状态筛选: {other}")));
        }
        None => None,
    };
    let page = state.db.bets().page(
        q.game.as_deref(),
        status,
        q.page.unwrap_or(1),
        q.page_size.unwrap_or(50),
    )?;
    Ok(Json(serde_json::to_value(page)?))
}

async fn bets_summary(
    State(state): State<AppState>,
    Query(q): Query<BetsQuery>,
) -> Result<Json<Value>, AppError> {
    if let Some(g) = q.game.as_deref().filter(|g| !g.trim().is_empty()) {
        game_or_err(g)?;
    }
    let summary = state.db.bets().summary(q.game.as_deref())?;
    Ok(Json(serde_json::to_value(summary)?))
}

#[derive(Deserialize)]
struct CheckBetsRequest {
    #[serde(default)]
    game: Option<String>,
    /// When true, already settled bets are recomputed from scratch. Any
    /// \`actual_amount\` the user entered is preserved.
    #[serde(default)]
    full: Option<bool>,
}

/// Settles pending bets. Called automatically after every sync (see
/// \`lib.rs\`) and exposed so the UI can force a re-check, for example after
/// importing corrected draw data.
async fn check_bets(
    State(state): State<AppState>,
    Json(req): Json<CheckBetsRequest>,
) -> Result<Json<Value>, AppError> {
    let game = req.game.as_deref().filter(|g| !g.trim().is_empty());
    if let Some(g) = game {
        game_or_err(g)?;
    }
    let games: Vec<&'static config::GameDef> = match game {
        Some(g) => vec![config::game(g).expect("checked above")],
        None => config::GAMES.iter().collect(),
    };
    let full = req.full.unwrap_or(false);
    // One cache covering every requested game: check_pending walks all bets
    // regardless of game, so a per-game cache would leave the other games'
    // records unsettled.
    let mut cache = Vec::new();
    for g in &games {
        cache.extend(draw_cache(&state.db, g.id));
    }
    let mut settled = 0usize;
    let mut won = 0usize;
    let mut still_pending = 0usize;
    let mut skipped = 0usize;
    for g in &games {
        let outcome = if full {
            state.db.bets().recheck_all(g.id, lookup(&cache))?
        } else {
            state.db.check_pending_bets(lookup(&cache))?
        };
        settled += outcome.settled;
        won += outcome.won;
        still_pending += outcome.still_pending;
        skipped += outcome.skipped;
    }
    Ok(Json(json!({
        "settled": settled,
        "won": won,
        "still_pending": still_pending,
        "skipped": skipped,
        "rechecked": full,
    })))
}

async fn delete_bet(
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> Result<Json<Value>, AppError> {
    if state.db.bets().delete(id)? {
        Ok(Json(json!({ "deleted": id })))
    } else {
        Err(AppError::not_found(format!("未找到编号 {id} 的购彩记录")))
    }
}

#[derive(Deserialize)]
struct ActualAmountRequest {
    /// In CNY. Omit or null to fall back to the config estimate again.
    #[serde(default)]
    amount: Option<f64>,
}

/// Records the real payout of a floating-tier prize, so the ledger stops
/// relying on the long-run estimate for that bet.
async fn set_actual_amount(
    State(state): State<AppState>,
    Path(id): Path<i64>,
    Json(req): Json<ActualAmountRequest>,
) -> Result<Json<Value>, AppError> {
    let amount = req.amount.filter(|a| a.is_finite() && *a >= 0.0);
    if state.db.bets().set_actual_amount(id, amount)? {
        Ok(Json(json!({ "id": id, "actual_amount": amount })))
    } else {
        Err(AppError::not_found(format!("未找到编号 {id} 的购彩记录")))
    }
}

/// Loads the newest issues used to settle pending bets. Bets almost always
/// target a recent issue, so a bounded window keeps this cheap while still
/// covering every realistic case.
fn draw_cache(db: &Db, game: &str) -> Vec<Draw> {
    db.recent(game, 400).unwrap_or_default()
}

/// A (game, issue) -> draw lookup over a preloaded window.
fn lookup(draws: &[Draw]) -> impl Fn(&str, &str) -> Option<Draw> + '_ {
    move |game: &str, issue: &str| {
        draws
            .iter()
            .find(|d| d.game == game && d.issue == issue)
            .cloned()
    }
}

async fn run_backtest(
    State(state): State<AppState>,
    Json(req): Json<backtest::BacktestRequest>,
) -> Result<Json<Value>, AppError> {
    let g = game_or_err(&req.game)?;
    let draws = draws_or_err(&state, &req.game)?;
    let value = backtest::run(&draws, g, &req)?;
    Ok(Json(value))
}

#[derive(Deserialize)]
struct SyncRequest {
    game: String,
    /// How much to fetch. `recent` (the default) reads only the newest
    /// official page — cheap enough to run often, and what the toolbar button
    /// wants when asking "did the draw land yet?". `official` walks every
    /// official page; `full` adds the 500.com backfill for 2003–2012.
    #[serde(default = "default_sync_mode")]
    mode: String,
    /// Deprecated alias for `mode: "full"`, honoured so a stale client keeps
    /// its full re-sync instead of silently getting a recent-only one.
    #[serde(default)]
    full: Option<bool>,
}

fn default_sync_mode() -> String {
    "recent".to_string()
}

/// What a sync request asks for.
#[derive(Debug)]
enum SyncScope {
    Recent,
    Official,
    Full,
}

fn sync_scope(req: &SyncRequest) -> Result<SyncScope, AppError> {
    match req.mode.trim().to_ascii_lowercase().as_str() {
        "" | "recent" if req.full == Some(true) => Ok(SyncScope::Full),
        "" | "recent" => Ok(SyncScope::Recent),
        "official" => Ok(SyncScope::Official),
        "full" => Ok(SyncScope::Full),
        other => Err(AppError::bad(format!(
            "未知的同步模式 {other}，可用：recent / official / full"
        ))),
    }
}

async fn sync(
    State(state): State<AppState>,
    Json(req): Json<SyncRequest>,
) -> Result<Json<Value>, AppError> {
    let g = game_or_err(&req.game)?;
    let draws = match sync_scope(&req)? {
        SyncScope::Recent => sources::fetch_recent(&req.game).await?,
        SyncScope::Official => sources::sync(&req.game, false, g).await?,
        SyncScope::Full => sources::sync(&req.game, true, g).await?,
    };
    let fetched = draws.len();
    let written = state.db.upsert_many(&draws, "official")?;
    // A fresh draw settles the bets waiting on it.
    let cache = draw_cache(&state.db, g.id);
    let checked = state.db.check_pending_bets(lookup(&cache))?;
    let total = state.db.count(&req.game)?;
    let latest = state.db.latest(&req.game)?;
    Ok(Json(json!({
        "game": g.id,
        "fetched": fetched,
        "written": written,
        "total": total,
        "latest": latest,
        "bets_settled": checked.settled,
        "bets_won": checked.won,
    })))
}

#[derive(Deserialize)]
struct ImportRequest {
    game: String,
    csv: String,
}

async fn import(
    State(state): State<AppState>,
    Json(req): Json<ImportRequest>,
) -> Result<Json<Value>, AppError> {
    let g = game_or_err(&req.game)?;
    let mut rdr = csv::ReaderBuilder::new()
        .has_headers(true)
        .flexible(true)
        .from_reader(req.csv.as_bytes());
    let mut draws = Vec::new();
    let mut skipped = 0usize;
    for rec in rdr.records() {
        let rec = rec?;
        if rec.len() < 4 {
            skipped += 1;
            continue;
        }
        let issue = rec.get(0).unwrap_or("").trim().to_string();
        let date = rec.get(1).unwrap_or("").trim().to_string();
        let primary = parse_list(rec.get(2).unwrap_or(""));
        let secondary = parse_list(rec.get(3).unwrap_or(""));
        let valid = !issue.is_empty()
            && date.len() >= 8
            && primary.len() == g.primary_count
            && secondary.len() == g.secondary_count
            && primary.iter().all(|&n| n >= 1 && n <= g.primary_max)
            && secondary.iter().all(|&n| n >= 1 && n <= g.secondary_max)
            && is_unique(&primary)
            && is_unique(&secondary);
        if !valid {
            skipped += 1;
            continue;
        }
        draws.push(Draw {
            game: g.id.into(),
            issue,
            date,
            primary,
            secondary,
            sales: None,
            pool: None,
        });
    }
    let written = state.db.upsert_many(&draws, "import")?;
    // Imported draws can settle bets whose issue was missing before.
    let cache = draw_cache(&state.db, g.id);
    let checked = state.db.check_pending_bets(lookup(&cache))?;
    Ok(Json(json!({
        "game": g.id,
        "parsed": draws.len(),
        "written": written,
        "skipped": skipped,
        "total": state.db.count(&req.game)?,
        "bets_settled": checked.settled,
        "bets_won": checked.won,
    })))
}

fn parse_list(s: &str) -> Vec<u8> {
    s.split(|c: char| c == ',' || c == '|' || c == '-' || c.is_whitespace())
        .filter_map(|x| x.trim().parse::<u8>().ok())
        .collect()
}

fn is_unique(nums: &[u8]) -> bool {
    let mut v = nums.to_vec();
    v.sort_unstable();
    v.dedup();
    v.len() == nums.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn req(mode: &str, full: Option<bool>) -> SyncRequest {
        SyncRequest {
            game: "ssq".to_string(),
            mode: mode.to_string(),
            full,
        }
    }

    #[test]
    fn recent_is_the_default_scope() {
        assert!(matches!(
            sync_scope(&req("", None)).unwrap(),
            SyncScope::Recent
        ));
        assert!(matches!(
            sync_scope(&req("recent", None)).unwrap(),
            SyncScope::Recent
        ));
        // Case and stray whitespace don't matter.
        assert!(matches!(
            sync_scope(&req(" Recent ", None)).unwrap(),
            SyncScope::Recent
        ));
    }

    #[test]
    fn official_and_full_are_selectable() {
        assert!(matches!(
            sync_scope(&req("official", None)).unwrap(),
            SyncScope::Official
        ));
        assert!(matches!(
            sync_scope(&req("full", None)).unwrap(),
            SyncScope::Full
        ));
    }

    #[test]
    fn the_old_full_flag_still_means_a_full_sync() {
        // A stale client that only knows the old flag keeps its full re-sync
        // instead of silently getting a recent-only one.
        assert!(matches!(
            sync_scope(&req("", Some(true))).unwrap(),
            SyncScope::Full
        ));
        assert!(matches!(
            sync_scope(&req("recent", Some(true))).unwrap(),
            SyncScope::Full
        ));
        assert!(matches!(
            sync_scope(&req("recent", Some(false))).unwrap(),
            SyncScope::Recent
        ));
    }

    #[test]
    fn an_unknown_mode_is_rejected() {
        let err = sync_scope(&req("everything", None)).unwrap_err();
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert!(err.message.contains("recent"));
    }
}
