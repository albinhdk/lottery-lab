//! Personal bet records and automatic prize checking.
//!
//! A bet is one hand-picked ticket against one specific issue. Records live
//! in the same SQLite database (and the same connection) as the draws, so a
//! draw that arrives through the periodic sync can settle every pending bet
//! with a purely local calculation -- no extra network call, and \`draws\` is
//! never modified.
//!
//! Tier 1/2 amounts are long-run estimates from \`config::prize\` and are
//! flagged \`estimated\`; the user can overwrite them with the real payout via
//! \`actual_amount\` once the official numbers are known.

use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};

use crate::{
    config::{self, GameDef},
    models::Draw,
    prize,
};

/// Lifecycle of one bet. \`pending\` becomes \`won\` or \`lost\` once the issue
/// has been drawn and checked.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BetStatus {
    Pending,
    Won,
    Lost,
}

impl BetStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            BetStatus::Pending => "pending",
            BetStatus::Won => "won",
            BetStatus::Lost => "lost",
        }
    }

    fn from_str(value: &str) -> Self {
        match value {
            "won" => BetStatus::Won,
            "lost" => BetStatus::Lost,
            _ => BetStatus::Pending,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bet {
    pub id: i64,
    pub game: String,
    pub game_name: String,
    pub issue: String,
    /// Draw date of the issue, once it has been drawn. Empty while pending.
    pub date: String,
    pub primary: Vec<u8>,
    pub secondary: Vec<u8>,
    pub multiple: u32,
    pub note: String,
    pub status: BetStatus,
    pub tier: u8,
    pub tier_name: String,
    pub primary_hits: usize,
    pub secondary_hits: usize,
    pub matched_primary: Vec<u8>,
    pub matched_secondary: Vec<u8>,
    /// Prize for one ticket, from the config table.
    pub amount: f64,
    /// Actual payout recorded by the user, when known.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub actual_amount: Option<f64>,
    /// True while \`amount\` is a tier-1/2 estimate.
    pub estimated: bool,
    /// Total stake: multiple x ticket price.
    pub cost: f64,
    /// Total payout: multiple x (actual_amount or amount).
    pub payout: f64,
    pub created_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub checked_at: Option<String>,
}

impl Bet {
    pub fn won(&self) -> bool {
        self.status == BetStatus::Won
    }
}

/// One entry of a multi-bet submission.
#[derive(Debug, Clone, Deserialize)]
pub struct BetInput {
    pub issue: String,
    pub primary: Vec<u8>,
    pub secondary: Vec<u8>,
    #[serde(default = "default_multiple")]
    pub multiple: u32,
    #[serde(default)]
    pub note: String,
}

fn default_multiple() -> u32 {
    1
}

#[derive(Debug, Clone, Serialize)]
pub struct BetSummary {
    pub total: usize,
    pub pending: usize,
    pub won: usize,
    pub lost: usize,
    /// Total stake across all filtered bets, in CNY.
    pub cost: f64,
    /// Total payout across all filtered bets, in CNY.
    pub payout: f64,
    /// payout - cost; negative is the expected long-run outcome.
    pub net: f64,
    /// How much of \`payout\` rests on tier-1/2 estimates rather than on
    /// payouts the user confirmed.
    pub estimated_payout: f64,
    pub by_tier: Vec<TierCount>,
}

#[derive(Debug, Clone, Serialize)]
pub struct TierCount {
    pub game: String,
    pub game_name: String,
    pub tier: u8,
    pub tier_name: String,
    pub count: usize,
    /// Prize of one ticket at this tier, from the config table.
    pub amount: f64,
    /// Sum over bets, honouring \`actual_amount\` when present.
    pub payout: f64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Page<T> {
    pub items: Vec<T>,
    pub page: usize,
    pub page_size: usize,
    pub total: usize,
    pub pages: usize,
}

/// Result of one checking pass.
#[derive(Debug, Clone, Serialize)]
pub struct CheckOutcome {
    /// Bets whose status changed from pending to settled in this pass.
    pub settled: usize,
    pub won: usize,
    /// Pending bets whose issue is not drawn yet -- nothing to do for them.
    pub still_pending: usize,
    /// Bets that were already settled and were left untouched.
    pub skipped: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct InsertOutcome {
    pub inserted: usize,
    pub duplicates: usize,
}

/// Bet storage. Shares the connection with the draws table so both live in
/// one database file, one write lock and one WAL.
pub struct BetStore {
    conn: Arc<Mutex<Connection>>,
}

const BET_COLUMNS: &str = "id, game, issue, draw_date, primary_numbers, secondary_numbers, \
     multiple, note, status, tier, primary_hits, secondary_hits, matched_primary, \
     matched_secondary, amount, actual_amount, estimated, cost, created_at, checked_at";

impl BetStore {
    pub fn new(conn: Arc<Mutex<Connection>>) -> Self {
        Self { conn }
    }

    pub fn ensure_schema(&self) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS bets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                game TEXT NOT NULL,
                issue TEXT NOT NULL,
                draw_date TEXT NOT NULL DEFAULT '',
                primary_numbers TEXT NOT NULL,
                secondary_numbers TEXT NOT NULL,
                multiple INTEGER NOT NULL DEFAULT 1,
                note TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'pending',
                tier INTEGER NOT NULL DEFAULT 0,
                primary_hits INTEGER NOT NULL DEFAULT 0,
                secondary_hits INTEGER NOT NULL DEFAULT 0,
                matched_primary TEXT NOT NULL DEFAULT '',
                matched_secondary TEXT NOT NULL DEFAULT '',
                amount REAL NOT NULL DEFAULT 0,
                actual_amount REAL,
                estimated INTEGER NOT NULL DEFAULT 0,
                cost REAL NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                checked_at TEXT
             );
             CREATE INDEX IF NOT EXISTS idx_bets_game_issue ON bets(game, issue);
             CREATE INDEX IF NOT EXISTS idx_bets_status ON bets(status);
             CREATE INDEX IF NOT EXISTS idx_bets_created ON bets(created_at);",
        )
        .context("create bets tables")?;
        Ok(())
    }

    /// Inserts bets. Duplicate (game, issue, numbers, multiple) rows are
    /// reported in \`duplicates\` and skipped, so a double tap on the save
    /// button cannot create phantom records.
    pub fn insert(&self, game: &str, inputs: &[BetInput], price: f64) -> Result<InsertOutcome> {
        if inputs.is_empty() {
            return Ok(InsertOutcome {
                inserted: 0,
                duplicates: 0,
            });
        }
        let mut conn = self.conn.lock().unwrap();
        let tx = conn.transaction()?;
        let mut inserted = 0usize;
        let mut duplicates = 0usize;
        {
            let mut existing = tx.prepare(
                "SELECT 1 FROM bets WHERE game = ?1 AND issue = ?2
                 AND primary_numbers = ?3 AND secondary_numbers = ?4 AND multiple = ?5 LIMIT 1",
            )?;
            let mut stmt = tx.prepare(
                "INSERT INTO bets
                    (game, issue, primary_numbers, secondary_numbers, multiple, note, cost)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            )?;
            for input in inputs {
                let primary = normalize(&input.primary);
                let secondary = normalize(&input.secondary);
                let multiple = input.multiple.clamp(1, 1000);
                let key_primary = join_numbers(&primary);
                let key_secondary = join_numbers(&secondary);
                let seen = existing.exists(params![
                    game,
                    input.issue.trim(),
                    key_primary,
                    key_secondary,
                    multiple
                ])?;
                if seen {
                    duplicates += 1;
                    continue;
                }
                stmt.execute(params![
                    game,
                    input.issue.trim(),
                    key_primary,
                    key_secondary,
                    multiple,
                    input.note.trim(),
                    price * multiple as f64,
                ])?;
                inserted += 1;
            }
        }
        tx.commit()?;
        Ok(InsertOutcome {
            inserted,
            duplicates,
        })
    }

    pub fn delete(&self, id: i64) -> Result<bool> {
        let conn = self.conn.lock().unwrap();
        let n = conn.execute("DELETE FROM bets WHERE id = ?1", params![id])?;
        Ok(n > 0)
    }

    /// Records the real payout for a floating-tier bet. \`None\` clears it and
    /// falls back to the estimate again.
    pub fn set_actual_amount(&self, id: i64, amount: Option<f64>) -> Result<bool> {
        let conn = self.conn.lock().unwrap();
        let n = conn.execute(
            "UPDATE bets SET actual_amount = ?2 WHERE id = ?1",
            params![id, amount],
        )?;
        Ok(n > 0)
    }

    pub fn update_note(&self, id: i64, note: &str) -> Result<bool> {
        let conn = self.conn.lock().unwrap();
        let n = conn.execute(
            "UPDATE bets SET note = ?2 WHERE id = ?1",
            params![id, note.trim()],
        )?;
        Ok(n > 0)
    }

    pub fn get(&self, id: i64) -> Result<Option<Bet>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(&format!(
            "SELECT {BET_COLUMNS} FROM bets WHERE id = ?1"
        ))?;
        let mut rows = stmt.query(params![id])?;
        Ok(rows.next()?.map(row_to_bet).transpose()?)
    }

    /// Newest bets first, optionally filtered by game and status.
    pub fn page(
        &self,
        game: Option<&str>,
        status: Option<BetStatus>,
        page: usize,
        page_size: usize,
    ) -> Result<Page<Bet>> {
        let conn = self.conn.lock().unwrap();
        let mut where_sql = String::from("WHERE 1 = 1");
        let mut args: Vec<String> = Vec::new();
        if let Some(g) = game.filter(|g| !g.trim().is_empty()) {
            where_sql.push_str(" AND game = ?");
            args.push(g.trim().to_string());
        }
        if let Some(s) = status {
            where_sql.push_str(" AND status = ?");
            args.push(s.as_str().to_string());
        }
        let total: i64 = {
            let sql = format!("SELECT COUNT(*) FROM bets {where_sql}");
            let mut stmt = conn.prepare(&sql)?;
            let params: Vec<&dyn rusqlite::ToSql> =
                args.iter().map(|s| s as &dyn rusqlite::ToSql).collect();
            stmt.query_row(params.as_slice(), |r| r.get(0))?
        };
        let page = page.max(1);
        let page_size = page_size.clamp(1, 200);
        let offset = (page - 1) * page_size;
        let sql = format!(
            "SELECT {BET_COLUMNS} FROM bets {where_sql}
             ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?"
        );
        let mut stmt = conn.prepare(&sql)?;
        let mut params: Vec<&dyn rusqlite::ToSql> =
            args.iter().map(|s| s as &dyn rusqlite::ToSql).collect();
        let limit = page_size as i64;
        let off = offset as i64;
        params.push(&limit);
        params.push(&off);
        let mut rows = stmt.query(params.as_slice())?;
        let mut items = Vec::new();
        while let Some(row) = rows.next()? {
            items.push(row_to_bet(row)?);
        }
        let total = total as usize;
        Ok(Page {
            items,
            page,
            page_size,
            total,
            pages: total.div_ceil(page_size),
        })
    }

    pub fn summary(&self, game: Option<&str>) -> Result<BetSummary> {
        let conn = self.conn.lock().unwrap();
        let filter = game.filter(|g| !g.trim().is_empty());
        let (where_sql, args): (String, Vec<String>) = match filter {
            Some(g) => (String::from("WHERE game = ?1"), vec![g.trim().to_string()]),
            None => (String::from("WHERE 1 = 1"), Vec::new()),
        };
        let params: Vec<&dyn rusqlite::ToSql> =
            args.iter().map(|s| s as &dyn rusqlite::ToSql).collect();

        let mut total = 0usize;
        let mut pending = 0usize;
        let mut won = 0usize;
        let mut lost = 0usize;
        let mut cost = 0.0f64;
        let mut payout = 0.0f64;
        let mut estimated_payout = 0.0f64;
        {
            let sql = format!(
                "SELECT status,
                        COUNT(*),
                        COALESCE(SUM(cost), 0),
                        COALESCE(SUM(CASE WHEN actual_amount IS NOT NULL
                                          THEN actual_amount ELSE amount END), 0),
                        COALESCE(SUM(CASE WHEN estimated = 1 AND tier > 0
                                          THEN (CASE WHEN actual_amount IS NOT NULL
                                                 THEN actual_amount ELSE amount END)
                                          ELSE 0 END), 0)
                 FROM bets {where_sql} GROUP BY status"
            );
            let mut stmt = conn.prepare(&sql)?;
            let mut rows = stmt.query(params.as_slice())?;
            while let Some(row) = rows.next()? {
                let status: String = row.get(0)?;
                let count: i64 = row.get(1)?;
                total += count as usize;
                cost += row.get::<_, f64>(2)?;
                payout += row.get::<_, f64>(3)?;
                estimated_payout += row.get::<_, f64>(4)?;
                match BetStatus::from_str(&status) {
                    BetStatus::Pending => pending += count as usize,
                    BetStatus::Won => won += count as usize,
                    BetStatus::Lost => lost += count as usize,
                }
            }
        }

        let tier_sql = format!(
            "SELECT game, tier,
                    COUNT(*),
                    COALESCE(SUM(CASE WHEN actual_amount IS NOT NULL
                                      THEN actual_amount ELSE amount END), 0)
             FROM bets {where_sql} AND tier > 0
             GROUP BY game, tier
             ORDER BY game, tier"
        );
        let mut by_tier = Vec::new();
        {
            let mut stmt = conn.prepare(&tier_sql)?;
            let mut rows = stmt.query(params.as_slice())?;
            while let Some(row) = rows.next()? {
                let game_id: String = row.get(0)?;
                let tier: u8 = row.get(1)?;
                let count: i64 = row.get(2)?;
                let tier_payout: f64 = row.get(3)?;
                let def = config::game(&game_id);
                by_tier.push(TierCount {
                    game: game_id.clone(),
                    game_name: def.map(|g| g.name.to_string()).unwrap_or(game_id),
                    tier,
                    tier_name: config::tier_name(def.map(|g| g.id).unwrap_or(""), tier).to_string(),
                    count: count as usize,
                    amount: def.map(|g| tier_amount(g, tier)).unwrap_or(0.0),
                    payout: tier_payout,
                });
            }
        }

        Ok(BetSummary {
            total,
            pending,
            won,
            lost,
            cost,
            payout,
            net: payout - cost,
            estimated_payout,
            by_tier,
        })
    }

    /// Settles every pending bet whose issue has been drawn.
    ///
    /// \`draws_for\` is consulted per bet, so the caller controls how draws are
    /// loaded. Bets whose issue is not drawn yet are left pending, and bets
    /// that were already settled are never recomputed, which keeps a manual
    /// \`actual_amount\` entry intact.
    pub fn check_pending<F>(&self, draws_for: F) -> Result<CheckOutcome>
    where
        F: Fn(&str, &str) -> Option<Draw>,
    {
        struct Row {
            id: i64,
            game: String,
            issue: String,
            primary: Vec<u8>,
            secondary: Vec<u8>,
            multiple: i64,
            status: String,
        }

        let mut conn = self.conn.lock().unwrap();
        let tx = conn.transaction()?;
        let mut settled = 0usize;
        let mut won = 0usize;
        let mut still_pending = 0usize;
        let mut skipped = 0usize;
        {
            let mut rows_vec = Vec::new();
            {
                let mut select = tx.prepare(
                    "SELECT id, game, issue, primary_numbers, secondary_numbers, multiple, status
                     FROM bets ORDER BY id",
                )?;
                let mut rows = select.query([])?;
                while let Some(row) = rows.next()? {
                    rows_vec.push(Row {
                        id: row.get(0)?,
                        game: row.get(1)?,
                        issue: row.get(2)?,
                        primary: parse_numbers(&row.get::<_, String>(3)?),
                        secondary: parse_numbers(&row.get::<_, String>(4)?),
                        multiple: row.get(5)?,
                        status: row.get(6)?,
                    });
                }
            }
            let mut update = tx.prepare(
                "UPDATE bets SET
                    draw_date = ?2, status = ?3, tier = ?4, primary_hits = ?5,
                    secondary_hits = ?6, matched_primary = ?7, matched_secondary = ?8,
                    amount = ?9, estimated = ?10, cost = ?11, checked_at = datetime('now')
                 WHERE id = ?1",
            )?;
            for row in rows_vec {
                if BetStatus::from_str(&row.status) != BetStatus::Pending {
                    skipped += 1;
                    continue;
                }
                let Some(draw) = draws_for(&row.game, &row.issue) else {
                    still_pending += 1;
                    continue;
                };
                let Some(game_def) = config::game(&row.game) else {
                    still_pending += 1;
                    continue;
                };
                let check = prize::evaluate(&draw, game_def, &row.primary, &row.secondary);
                let new_status = if check.tier > 0 {
                    BetStatus::Won
                } else {
                    BetStatus::Lost
                };
                let cost = game_def.price * row.multiple as f64;
                update.execute(params![
                    row.id,
                    draw.date,
                    new_status.as_str(),
                    check.tier,
                    check.primary_hits as i64,
                    check.secondary_hits as i64,
                    join_numbers(&check.matched_primary),
                    join_numbers(&check.matched_secondary),
                    check.amount,
                    if check.estimated { 1i64 } else { 0i64 },
                    cost,
                ])?;
                settled += 1;
                if new_status == BetStatus::Won {
                    won += 1;
                }
            }
        }
        tx.commit()?;
        Ok(CheckOutcome {
            settled,
            won,
            still_pending,
            skipped,
        })
    }

    /// Re-checks one game's settled bets from scratch. Used by the manual
    /// "re-check" action and after an import that fixed a bad draw. Any
    /// \`actual_amount\` the user entered is preserved.
    ///
    /// \`game\` is mandatory: the reset and the settlement must cover
    /// the same rows, otherwise a caller looping over games would wipe the
    /// other games' results with a cache that cannot settle them.
    pub fn recheck_all<F>(&self, game: &str, draws_for: F) -> Result<CheckOutcome>
    where
        F: Fn(&str, &str) -> Option<Draw>,
    {
        {
            let conn = self.conn.lock().unwrap();
            conn.execute(
                "UPDATE bets SET status = 'pending', draw_date = '', tier = 0,
                 primary_hits = 0, secondary_hits = 0, matched_primary = '',
                 matched_secondary = '', amount = 0, estimated = 0, checked_at = NULL
                 WHERE game = ?1 AND (tier > 0 OR status <> 'pending')",
                params![game],
            )?;
        }
        self.check_pending(draws_for)
    }
}

/// Unit amount for a tier, reconstructed from the game's own prize table.
fn tier_amount(game: &GameDef, tier: u8) -> f64 {
    let patterns: &[(usize, usize)] = match game.id {
        "ssq" => &[
            (6, 1),
            (6, 0),
            (5, 1),
            (5, 0),
            (4, 1),
            (4, 0),
            (3, 1),
            (0, 1),
        ],
        "dlt" => &[
            (5, 2),
            (5, 1),
            (5, 0),
            (4, 2),
            (4, 1),
            (3, 2),
            (4, 0),
            (3, 1),
            (3, 0),
            (0, 2),
        ],
        _ => &[],
    };
    for &(p, s) in patterns {
        let (t, amount) = config::prize(game.id, p, s);
        if t == tier {
            return amount;
        }
    }
    0.0
}

fn row_to_bet(row: &rusqlite::Row<'_>) -> rusqlite::Result<Bet> {
    let game: String = row.get(1)?;
    let tier: u8 = row.get(9)?;
    let actual_amount: Option<f64> = row.get(15)?;
    let multiple: i64 = row.get(6)?;
    let status = BetStatus::from_str(&row.get::<_, String>(8)?);
    let amount: f64 = row.get(14)?;
    let cost: f64 = row.get(17)?;
    let effective = actual_amount.unwrap_or(amount);
    let game_name = config::game(&game)
        .map(|g| g.name.to_string())
        .unwrap_or_else(|| game.clone());
    Ok(Bet {
        id: row.get(0)?,
        game: game.clone(),
        game_name,
        issue: row.get(2)?,
        date: row.get(3)?,
        primary: parse_numbers(&row.get::<_, String>(4)?),
        secondary: parse_numbers(&row.get::<_, String>(5)?),
        multiple: multiple.max(0) as u32,
        note: row.get(7)?,
        status,
        tier,
        tier_name: config::tier_name(&game, tier).to_string(),
        primary_hits: row.get::<_, i64>(10)? as usize,
        secondary_hits: row.get::<_, i64>(11)? as usize,
        matched_primary: parse_numbers(&row.get::<_, String>(12)?),
        matched_secondary: parse_numbers(&row.get::<_, String>(13)?),
        amount,
        actual_amount,
        estimated: row.get::<_, i64>(16)? != 0,
        cost,
        payout: if status == BetStatus::Won {
            effective * multiple.max(0) as f64
        } else {
            0.0
        },
        created_at: row.get(18)?,
        checked_at: row.get(19)?,
    })
}

fn normalize(nums: &[u8]) -> Vec<u8> {
    let mut v = nums.to_vec();
    v.sort_unstable();
    v.dedup();
    v
}

fn join_numbers(nums: &[u8]) -> String {
    nums.iter()
        .map(|n| n.to_string())
        .collect::<Vec<_>>()
        .join(",")
}

fn parse_numbers(s: &str) -> Vec<u8> {
    s.split(',')
        .filter_map(|x| x.trim().parse::<u8>().ok())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> BetStore {
        let conn = Arc::new(Mutex::new(Connection::open_in_memory().unwrap()));
        let store = BetStore::new(conn);
        store.ensure_schema().unwrap();
        store
    }

    fn draw(game: &str, issue: &str, primary: Vec<u8>, secondary: Vec<u8>) -> Draw {
        Draw {
            game: game.into(),
            issue: issue.into(),
            date: "2026-01-01".into(),
            primary,
            secondary,
            sales: None,
            pool: None,
        }
    }

    fn bet(issue: &str, primary: Vec<u8>, secondary: Vec<u8>) -> BetInput {
        BetInput {
            issue: issue.into(),
            primary,
            secondary,
            multiple: 1,
            note: String::new(),
        }
    }

    fn draws_map(draws: Vec<Draw>) -> impl Fn(&str, &str) -> Option<Draw> {
        move |game: &str, issue: &str| {
            draws
                .iter()
                .find(|d| d.game == game && d.issue == issue)
                .cloned()
        }
    }

    #[test]
    fn insert_deduplicates_identical_bets() {
        let store = store();
        let out = store
            .insert(
                "ssq",
                &[
                    bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7]),
                    bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7]),
                ],
                2.0,
            )
            .unwrap();
        assert_eq!(out.inserted, 1);
        assert_eq!(out.duplicates, 1);
        assert_eq!(store.page(None, None, 1, 10).unwrap().total, 1);
    }

    #[test]
    fn different_multiple_is_a_separate_bet() {
        let store = store();
        let mut b = bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7]);
        b.multiple = 2;
        store
            .insert(
                "ssq",
                &[bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7]), b],
                2.0,
            )
            .unwrap();
        assert_eq!(store.page(None, None, 1, 10).unwrap().total, 2);
    }

    #[test]
    fn numbers_are_normalized_before_storage() {
        let store = store();
        store
            .insert(
                "ssq",
                &[bet("2026001", vec![6, 1, 3, 2, 5, 4], vec![9])],
                2.0,
            )
            .unwrap();
        let row = store.get(1).unwrap().unwrap();
        assert_eq!(row.primary, vec![1, 2, 3, 4, 5, 6]);
    }

    #[test]
    fn check_settles_pending_bets_against_drawn_issues() {
        let store = store();
        store
            .insert(
                "ssq",
                &[
                    bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7]),
                    bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![8]),
                    bet("2026002", vec![1, 2, 3, 4, 5, 6], vec![7]),
                ],
                2.0,
            )
            .unwrap();
        let draws = vec![draw("ssq", "2026001", vec![1, 2, 3, 4, 5, 6], vec![7])];
        let outcome = store.check_pending(draws_map(draws)).unwrap();
        assert_eq!(outcome.settled, 2);
        // 6 red + blue 7 is tier 1; 6 red + blue 8 is tier 2. Both win.
        assert_eq!(outcome.won, 2);
        assert_eq!(outcome.still_pending, 1);

        let page = store.page(None, None, 1, 10).unwrap();
        // Two bets share the blue ball, so match on issue as well.
        let winner = page
            .items
            .iter()
            .find(|b| b.issue == "2026001" && b.secondary == vec![7])
            .expect("winning bet kept");
        assert_eq!(winner.tier, 1);
        assert_eq!(winner.tier_name, "一等奖");
        assert!(winner.estimated);
        assert_eq!(winner.payout, 7_000_000.0);
        assert_eq!(winner.date, "2026-01-01");
        assert_eq!(winner.matched_primary, vec![1, 2, 3, 4, 5, 6]);
        let runner_up = page
            .items
            .iter()
            .find(|b| b.issue == "2026001" && b.secondary == vec![8])
            .expect("runner-up bet kept");
        assert_eq!(runner_up.tier, 2);
        assert_eq!(runner_up.tier_name, "二等奖");
        assert_eq!(runner_up.payout, 150_000.0);
        // The third bet targets an undrawn issue and stays pending.
        let pending = page
            .items
            .iter()
            .find(|b| b.issue == "2026002")
            .expect("pending bet kept");
        assert_eq!(pending.status, BetStatus::Pending);
    }

    #[test]
    fn check_is_idempotent() {
        let store = store();
        store
            .insert("ssq", &[bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7])], 2.0)
            .unwrap();
        let draws = vec![draw("ssq", "2026001", vec![1, 2, 3, 4, 5, 6], vec![7])];
        let first = store.check_pending(draws_map(draws.clone())).unwrap();
        let second = store.check_pending(draws_map(draws)).unwrap();
        assert_eq!(first.settled, 1);
        assert_eq!(second.settled, 0);
        assert_eq!(second.skipped, 1);
    }

    #[test]
    fn cost_scales_with_multiple() {
        let store = store();
        let mut input = bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7]);
        input.multiple = 5;
        store.insert("ssq", &[input], 2.0).unwrap();
        assert_eq!(store.get(1).unwrap().unwrap().cost, 10.0);
    }

    #[test]
    fn actual_amount_overrides_the_estimate() {
        let store = store();
        store
            .insert("ssq", &[bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7])], 2.0)
            .unwrap();
        store
            .check_pending(draws_map(vec![draw(
                "ssq",
                "2026001",
                vec![1, 2, 3, 4, 5, 6],
                vec![7],
            )]))
            .unwrap();
        assert!(store.set_actual_amount(1, Some(6_543_210.0)).unwrap());
        let row = store.get(1).unwrap().unwrap();
        assert_eq!(row.payout, 6_543_210.0);
        assert_eq!(row.actual_amount, Some(6_543_210.0));
    }

    #[test]
    fn summary_counts_stake_and_payout() {
        let store = store();
        store
            .insert(
                "ssq",
                &[
                    bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7]),
                    bet("2026001", vec![9, 10, 11, 12, 13, 14], vec![7]),
                    bet("2026009", vec![1, 2, 3, 4, 5, 6], vec![7]),
                ],
                2.0,
            )
            .unwrap();
        store
            .check_pending(draws_map(vec![draw(
                "ssq",
                "2026001",
                vec![1, 2, 3, 4, 5, 6],
                vec![7],
            )]))
            .unwrap();
        // Settled: tier 1 (7,000,000) and tier 6 (5, blue ball only).
        // The third bet targets an undrawn issue and stays pending.
        let summary = store.summary(None).unwrap();
        assert_eq!(summary.total, 3);
        assert_eq!(summary.pending, 1);
        assert_eq!(summary.won, 2);
        assert_eq!(summary.cost, 6.0);
        assert_eq!(summary.payout, 7_000_005.0);
        assert_eq!(summary.net, 6_999_999.0);
        assert_eq!(summary.by_tier.len(), 2);
        // Only the tier-1 payout rests on an estimate.
        assert_eq!(summary.estimated_payout, 7_000_000.0);
    }

    #[test]
    fn summary_can_filter_by_game() {
        let store = store();
        store
            .insert("ssq", &[bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7])], 2.0)
            .unwrap();
        store
            .insert(
                "dlt",
                &[BetInput {
                    issue: "26001".into(),
                    primary: vec![1, 2, 3, 4, 5],
                    secondary: vec![6, 7],
                    multiple: 1,
                    note: String::new(),
                }],
                2.0,
            )
            .unwrap();
        assert_eq!(store.summary(Some("ssq")).unwrap().total, 1);
        assert_eq!(store.summary(None).unwrap().total, 2);
    }

    #[test]
    fn recheck_recomputes_from_scratch() {
        let store = store();
        store
            .insert("ssq", &[bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7])], 2.0)
            .unwrap();
        store.check_pending(draws_map(vec![])).unwrap();
        assert_eq!(store.get(1).unwrap().unwrap().status, BetStatus::Pending);
        store
            .check_pending(draws_map(vec![draw(
                "ssq",
                "2026001",
                vec![1, 2, 3, 4, 5, 6],
                vec![7],
            )]))
            .unwrap();
        assert_eq!(store.get(1).unwrap().unwrap().status, BetStatus::Won);
        let outcome = store
            .recheck_all(
                "ssq",
                draws_map(vec![draw(
                    "ssq",
                    "2026001",
                    vec![1, 2, 3, 4, 5, 6],
                    vec![7],
                )]),
            )
            .unwrap();
        assert_eq!(outcome.settled, 1);
        assert_eq!(store.get(1).unwrap().unwrap().status, BetStatus::Won);
    }

    #[test]
    fn recheck_keeps_the_user_entered_amount() {
        let store = store();
        store
            .insert("ssq", &[bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7])], 2.0)
            .unwrap();
        store
            .check_pending(draws_map(vec![draw(
                "ssq",
                "2026001",
                vec![1, 2, 3, 4, 5, 6],
                vec![7],
            )]))
            .unwrap();
        store.set_actual_amount(1, Some(6_543_210.0)).unwrap();
        store
            .recheck_all(
                "ssq",
                draws_map(vec![draw(
                    "ssq",
                    "2026001",
                    vec![1, 2, 3, 4, 5, 6],
                    vec![7],
                )]),
            )
            .unwrap();
        assert_eq!(store.get(1).unwrap().unwrap().payout, 6_543_210.0);
    }

    #[test]
    fn recheck_scoped_to_one_game_keeps_the_other_games_results() {
        // Regression: recheck_all used to reset every game's rows while the
        // caller only supplied one game's draws, so a game loop left the
        // other games' settled bets stuck in "pending".
        let store = store();
        store
            .insert("ssq", &[bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7])], 2.0)
            .unwrap();
        store
            .insert(
                "dlt",
                &[BetInput {
                    issue: "26001".into(),
                    primary: vec![1, 2, 3, 4, 5],
                    secondary: vec![6, 7],
                    multiple: 1,
                    note: String::new(),
                }],
                2.0,
            )
            .unwrap();
        // Settle both.
        store
            .check_pending(draws_map(vec![
                draw("ssq", "2026001", vec![1, 2, 3, 4, 5, 6], vec![7]),
                draw("dlt", "26001", vec![1, 2, 3, 4, 5], vec![6, 7]),
            ]))
            .unwrap();
        assert_eq!(store.get(1).unwrap().unwrap().status, BetStatus::Won);
        assert_eq!(store.get(2).unwrap().unwrap().status, BetStatus::Won);

        // Re-check only dlt: the ssq bet must stay settled.
        let dlt_draws = vec![draw("dlt", "26001", vec![1, 2, 3, 4, 5], vec![6, 7])];
        store
            .recheck_all("dlt", draws_map(dlt_draws))
            .unwrap();
        assert_eq!(
            store.get(2).unwrap().unwrap().status,
            BetStatus::Won,
            "dlt bet is re-settled"
        );
        assert_eq!(
            store.get(1).unwrap().unwrap().status,
            BetStatus::Won,
            "ssq bet must not be reset by another game's recheck"
        );

        // Re-check only ssq with no draws available: dlt still survives.
        store.recheck_all("ssq", draws_map(vec![])).unwrap();
        assert_eq!(store.get(2).unwrap().unwrap().status, BetStatus::Won);
        assert_eq!(store.get(1).unwrap().unwrap().status, BetStatus::Pending);
    }

    #[test]
    fn delete_removes_only_the_requested_row() {
        let store = store();
        store
            .insert(
                "ssq",
                &[
                    bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7]),
                    bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![8]),
                ],
                2.0,
            )
            .unwrap();
        assert!(store.delete(1).unwrap());
        assert!(!store.delete(1).unwrap());
        assert_eq!(store.page(None, None, 1, 10).unwrap().total, 1);
    }

    #[test]
    fn page_filters_by_status_and_game() {
        let store = store();
        store
            .insert(
                "ssq",
                &[
                    bet("2026001", vec![1, 2, 3, 4, 5, 6], vec![7]),
                    bet("2026002", vec![1, 2, 3, 4, 5, 6], vec![7]),
                ],
                2.0,
            )
            .unwrap();
        store
            .check_pending(draws_map(vec![draw(
                "ssq",
                "2026001",
                vec![1, 2, 3, 4, 5, 6],
                vec![7],
            )]))
            .unwrap();
        assert_eq!(
            store.page(None, Some(BetStatus::Pending), 1, 10).unwrap().total,
            1
        );
        assert_eq!(
            store.page(Some("ssq"), Some(BetStatus::Won), 1, 10)
                .unwrap()
                .total,
            1
        );
        assert_eq!(store.page(Some("dlt"), None, 1, 10).unwrap().total, 0);
    }
}
