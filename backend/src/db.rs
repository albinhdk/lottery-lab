use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
use rusqlite::{params, Connection, OptionalExtension};

use crate::{
    bets::BetStore,
    models::{Draw, Page},
};

pub struct Db {
    conn: Arc<Mutex<Connection>>,
    bets: BetStore,
}

impl Db {
    pub fn open(path: &str) -> Result<Self> {
        if let Some(parent) = std::path::Path::new(path).parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).ok();
            }
        }
        let conn = Connection::open(path).with_context(|| format!("open sqlite db {path}"))?;
        conn.execute_batch(
            "PRAGMA journal_mode=WAL;
             PRAGMA synchronous=NORMAL;
             CREATE TABLE IF NOT EXISTS draws (
                game TEXT NOT NULL,
                issue TEXT NOT NULL,
                draw_date TEXT NOT NULL,
                primary_numbers TEXT NOT NULL,
                secondary_numbers TEXT NOT NULL,
                sales INTEGER,
                pool INTEGER,
                source TEXT,
                updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                PRIMARY KEY (game, issue)
             );
             CREATE INDEX IF NOT EXISTS idx_draws_game_date ON draws(game, draw_date);
             CREATE INDEX IF NOT EXISTS idx_draws_game_issue ON draws(game, issue);",
        )?;
        let conn = Arc::new(Mutex::new(conn));
        let bets = BetStore::new(conn.clone());
        bets.ensure_schema()?;
        Ok(Self { conn, bets })
    }

    /// Bet records share this database and connection, so a draw that lands
    /// through the sync can settle pending bets in the same transaction.
    pub fn bets(&self) -> &BetStore {
        &self.bets
    }

    /// Settles pending bets whose issue has since been drawn. The closure is a
    /// (game, issue) -> draw lookup, usually built from the draws the sync
    /// just fetched plus what is already in the database.
    pub fn check_pending_bets<F>(&self, cache: F) -> Result<crate::bets::CheckOutcome>
    where
        F: Fn(&str, &str) -> Option<Draw>,
    {
        self.bets.check_pending(cache)
    }
    pub fn upsert_many(&self, draws: &[Draw], source: &str) -> Result<usize> {
        if draws.is_empty() {
            return Ok(0);
        }
        let mut conn = self.conn.lock().unwrap();
        let tx = conn.transaction()?;
        let mut changed = 0usize;
        {
            let mut stmt = tx.prepare(
                "INSERT INTO draws (game, issue, draw_date, primary_numbers, secondary_numbers, sales, pool, source)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
                 ON CONFLICT(game, issue) DO UPDATE SET
                    draw_date = excluded.draw_date,
                    primary_numbers = excluded.primary_numbers,
                    secondary_numbers = excluded.secondary_numbers,
                    sales = COALESCE(excluded.sales, draws.sales),
                    pool = COALESCE(excluded.pool, draws.pool),
                    source = excluded.source,
                    updated_at = datetime('now')",
            )?;
            for d in draws {
                let primary = join_numbers(&d.primary);
                let secondary = join_numbers(&d.secondary);
                changed += stmt.execute(params![
                    d.game,
                    d.issue,
                    d.date,
                    primary,
                    secondary,
                    d.sales,
                    d.pool,
                    source
                ])?;
            }
        }
        tx.commit()?;
        Ok(changed)
    }

    pub fn count(&self, game: &str) -> Result<usize> {
        let conn = self.conn.lock().unwrap();
        let n: i64 = conn.query_row(
            "SELECT COUNT(*) FROM draws WHERE game = ?1",
            params![game],
            |r| r.get(0),
        )?;
        Ok(n as usize)
    }

    pub fn latest(&self, game: &str) -> Result<Option<Draw>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT game, issue, draw_date, primary_numbers, secondary_numbers, sales, pool
             FROM draws WHERE game = ?1 ORDER BY draw_date DESC, issue DESC LIMIT 1",
        )?;
        let mut rows = stmt.query(params![game])?;
        if let Some(row) = rows.next()? {
            Ok(Some(row_to_draw(row)?))
        } else {
            Ok(None)
        }
    }

    pub fn get(&self, game: &str, issue: &str) -> Result<Option<Draw>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT game, issue, draw_date, primary_numbers, secondary_numbers, sales, pool
             FROM draws WHERE game = ?1 AND issue = ?2",
        )?;
        let mut rows = stmt.query(params![game, issue])?;
        Ok(rows.next()?.map(row_to_draw).transpose()?)
    }
    pub fn page(
        &self,
        game: &str,
        page: usize,
        page_size: usize,
        query: Option<&str>,
        from: Option<&str>,
        to: Option<&str>,
    ) -> Result<Page<Draw>> {
        let conn = self.conn.lock().unwrap();
        let mut where_sql = String::from(" WHERE game = ?1");
        let mut args: Vec<String> = vec![game.to_string()];
        if let Some(q) = query.filter(|q| !q.trim().is_empty()) {
            where_sql.push_str(" AND issue LIKE ?");
            args.push(format!("%{}%", q.trim()));
        }
        if let Some(f) = from.filter(|f| !f.is_empty()) {
            where_sql.push_str(" AND draw_date >= ?");
            args.push(f.to_string());
        }
        if let Some(t) = to.filter(|t| !t.is_empty()) {
            where_sql.push_str(" AND draw_date <= ?");
            args.push(t.to_string());
        }
        let total: i64 = {
            let sql = format!("SELECT COUNT(*) FROM draws{where_sql}");
            let mut stmt = conn.prepare(&sql)?;
            let params: Vec<&dyn rusqlite::ToSql> =
                args.iter().map(|s| s as &dyn rusqlite::ToSql).collect();
            stmt.query_row(params.as_slice(), |r| r.get(0))?
        };
        let page = page.max(1);
        let page_size = page_size.clamp(1, 500);
        let offset = (page - 1) * page_size;
        let sql = format!(
            "SELECT game, issue, draw_date, primary_numbers, secondary_numbers, sales, pool
             FROM draws{where_sql} ORDER BY draw_date DESC, issue DESC LIMIT ? OFFSET ?"
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
            items.push(row_to_draw(row)?);
        }
        let total = total as usize;
        let pages = total.div_ceil(page_size);
        Ok(Page {
            items,
            page,
            page_size,
            total,
            pages,
        })
    }

    /// All draws for a game, oldest first (chronological order).
    pub fn all_asc(&self, game: &str) -> Result<Vec<Draw>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT game, issue, draw_date, primary_numbers, secondary_numbers, sales, pool
             FROM draws WHERE game = ?1 ORDER BY draw_date ASC, issue ASC",
        )?;
        let mut rows = stmt.query(params![game])?;
        let mut out = Vec::new();
        while let Some(row) = rows.next()? {
            out.push(row_to_draw(row)?);
        }
        Ok(out)
    }

    /// The most recent issues, newest first. Used by the bet form's issue
    /// picker and by the auto-checker's lookup cache.
    pub fn recent(&self, game: &str, limit: usize) -> Result<Vec<Draw>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT game, issue, draw_date, primary_numbers, secondary_numbers, sales, pool
             FROM draws WHERE game = ?1 ORDER BY draw_date DESC, issue DESC LIMIT ?2",
        )?;
        let mut rows = stmt.query(params![game, limit as i64])?;
        let mut out = Vec::new();
        while let Some(row) = rows.next()? {
            out.push(row_to_draw(row)?);
        }
        Ok(out)
    }

    /// Next issue after the newest known one, derived from the issue numbering
    /// scheme of each game. Returns None when there is no history yet.
    pub fn next_issue(&self, game: &str) -> Result<Option<String>> {
        let Some(latest) = self.latest(game)? else {
            return Ok(None);
        };
        Ok(next_issue_for(game, &latest.issue))
    }

    pub fn date_range(&self, game: &str) -> Result<Option<(String, String)>> {
        let conn = self.conn.lock().unwrap();
        let r: Option<(Option<String>, Option<String>)> = conn
            .query_row(
                "SELECT MIN(draw_date), MAX(draw_date) FROM draws WHERE game = ?1",
                params![game],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?;
        Ok(match r {
            Some((Some(a), Some(b))) => Some((a, b)),
            _ => None,
        })
    }
}

/// Issue numbering of the supported games, used to suggest the next issue.
///
/// 双色球 uses a zero-padded 4-digit year followed by a 3-digit sequence
/// (`2026125`), 大乐透 a 2-digit year plus a 3-digit sequence (`26124`).
/// Both roll the sequence over at the year boundary.
pub fn next_issue_for(game: &str, latest_issue: &str) -> Option<String> {
    let digits: String = latest_issue
        .chars()
        .filter(|c| c.is_ascii_digit())
        .collect();
    if digits.is_empty() {
        return None;
    }
    let (year_len, seq_len) = match game {
        "ssq" => (4usize, 3usize),
        "dlt" => (2usize, 3usize),
        _ => return None,
    };
    if digits.len() != year_len + seq_len {
        return None;
    }
    let year: u32 = digits[..year_len].parse().ok()?;
    let seq: u32 = digits[year_len..].parse().ok()?;
    let seq_max = 10u32.pow(seq_len as u32) - 1;
    if seq >= seq_max {
        let next_year = (year + 1) % 10u32.pow(year_len as u32);
        return Some(format!("{next_year:0year_len$}001"));
    }
    Some(format!("{year:0year_len$}{:0seq_len$}", seq + 1))
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

fn row_to_draw(row: &rusqlite::Row<'_>) -> rusqlite::Result<Draw> {
    Ok(Draw {
        game: row.get(0)?,
        issue: row.get(1)?,
        date: row.get(2)?,
        primary: parse_numbers(&row.get::<_, String>(3)?),
        secondary: parse_numbers(&row.get::<_, String>(4)?),
        sales: row.get(5)?,
        pool: row.get(6)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn db() -> Db {
        Db::open(":memory:").unwrap()
    }

    fn draw(game: &str, issue: &str) -> Draw {
        Draw {
            game: game.into(),
            issue: issue.into(),
            date: "2026-01-01".into(),
            primary: vec![1, 2, 3, 4, 5, 6],
            secondary: vec![7],
            sales: None,
            pool: None,
        }
    }

    #[test]
    fn creates_bets_tables_alongside_draws() {
        let db = db();
        assert_eq!(db.count("ssq").unwrap(), 0);
        assert_eq!(db.bets().page(None, None, 1, 10).unwrap().total, 0);
    }

    #[test]
    fn next_issue_follows_each_game_numbering() {
        assert_eq!(next_issue_for("ssq", "2026125").as_deref(), Some("2026126"));
        assert_eq!(next_issue_for("dlt", "26124").as_deref(), Some("26125"));
        // Both games run well under 999 issues a year, so a mid-year
        // sequence simply increments.
        assert_eq!(next_issue_for("ssq", "2026153").as_deref(), Some("2026154"));
        assert_eq!(next_issue_for("dlt", "26153").as_deref(), Some("26154"));
        // The sequence only rolls over when it is exhausted.
        assert_eq!(next_issue_for("ssq", "2026999").as_deref(), Some("2027001"));
        assert_eq!(next_issue_for("dlt", "26999").as_deref(), Some("27001"));
        // Unknown shapes yield no suggestion instead of a wrong one.
        assert_eq!(next_issue_for("ssq", "abc"), None);
        assert_eq!(next_issue_for("xxx", "2026125"), None);
    }

    #[test]
    fn next_issue_reads_the_latest_draw() {
        let db = db();
        assert_eq!(db.next_issue("ssq").unwrap(), None);
        db.upsert_many(&[draw("ssq", "2026125")], "official").unwrap();
        assert_eq!(db.next_issue("ssq").unwrap().as_deref(), Some("2026126"));
    }

    #[test]
    fn recent_returns_newest_first() {
        let db = db();
        db.upsert_many(
            &[
                draw("ssq", "2026123"),
                draw("ssq", "2026124"),
                draw("ssq", "2026125"),
            ],
            "official",
        )
        .unwrap();
        let issues: Vec<String> = db
            .recent("ssq", 2)
            .unwrap()
            .into_iter()
            .map(|d| d.issue)
            .collect();
        assert_eq!(issues, vec!["2026125", "2026124"]);
    }

    #[test]
    fn check_pending_bets_settles_against_stored_draws() {
        let db = db();
        db.upsert_many(&[draw("ssq", "2026125")], "official").unwrap();
        db.bets()
            .insert(
                "ssq",
                &[crate::bets::BetInput {
                    issue: "2026125".into(),
                    primary: vec![1, 2, 3, 4, 5, 6],
                    secondary: vec![7],
                    multiple: 1,
                    note: String::new(),
                }],
                2.0,
            )
            .unwrap();
        let cache: Vec<Draw> = db.recent("ssq", 100).unwrap();
        let outcome = db
            .check_pending_bets(|game, issue| {
                cache
                    .iter()
                    .find(|d| d.game == game && d.issue == issue)
                    .cloned()
            })
            .unwrap();
        assert_eq!(outcome.settled, 1);
        assert_eq!(outcome.won, 1);
        let bet = db.bets().get(1).unwrap().unwrap();
        assert_eq!(bet.tier, 1);
    }
}
