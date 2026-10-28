use std::sync::Mutex;

use anyhow::{Context, Result};
use rusqlite::{params, Connection, OptionalExtension};

use crate::models::{Draw, Page};

pub struct Db {
    conn: Mutex<Connection>,
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
        Ok(Self {
            conn: Mutex::new(conn),
        })
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
