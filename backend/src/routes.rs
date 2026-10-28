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
    analysis, backtest, config, db::Db, models::Draw, sources,
    strategies::{StrategyKind, StrategyRunner},
};

#[derive(Clone)]
pub struct AppState {
    pub db: Arc<Db>,
}

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
        None => Err(AppError {
            status: StatusCode::NOT_FOUND,
            message: format!("未找到 {game} 期号 {issue}"),
        }),
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
    #[serde(default)]
    full: Option<bool>,
}

async fn sync(
    State(state): State<AppState>,
    Json(req): Json<SyncRequest>,
) -> Result<Json<Value>, AppError> {
    let g = game_or_err(&req.game)?;
    let full = req.full.unwrap_or(true);
    let draws = sources::sync(&req.game, full, g).await?;
    let fetched = draws.len();
    let written = state.db.upsert_many(&draws, "official")?;
    let total = state.db.count(&req.game)?;
    let latest = state.db.latest(&req.game)?;
    Ok(Json(json!({
        "game": g.id,
        "fetched": fetched,
        "written": written,
        "total": total,
        "latest": latest,
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
    Ok(Json(json!({
        "game": g.id,
        "parsed": draws.len(),
        "written": written,
        "skipped": skipped,
        "total": state.db.count(&req.game)?,
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
