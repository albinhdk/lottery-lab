use serde::Serialize;

#[derive(Debug, Clone, Copy, Serialize)]
pub struct GameDef {
    pub id: &'static str,
    pub name: &'static str,
    pub primary_label: &'static str,
    pub primary_count: usize,
    pub primary_max: u8,
    pub secondary_label: &'static str,
    pub secondary_count: usize,
    pub secondary_max: u8,
    /// Price of one basic ticket in CNY.
    pub price: f64,
    /// Floating prize tiers are estimates; fixed tiers are exact.
    pub prize_note: &'static str,
}

pub const GAMES: [GameDef; 2] = [
    GameDef {
        id: "ssq",
        name: "双色球",
        primary_label: "红球",
        primary_count: 6,
        primary_max: 33,
        secondary_label: "蓝球",
        secondary_count: 1,
        secondary_max: 16,
        price: 2.0,
        prize_note: "一、二等奖为浮动奖金，回测按一等奖 700 万、二等奖 15 万估算；三至六等奖为固定奖金。",
    },
    GameDef {
        id: "dlt",
        name: "超级大乐透",
        primary_label: "前区",
        primary_count: 5,
        primary_max: 35,
        secondary_label: "后区",
        secondary_count: 2,
        secondary_max: 12,
        price: 2.0,
        prize_note: "一、二等奖为浮动奖金，回测按一等奖 1000 万、二等奖 15 万估算；三至九等奖为固定奖金。",
    },
];

pub fn game(id: &str) -> Option<&'static GameDef> {
    GAMES.iter().find(|g| g.id == id)
}

/// Returns (prize tier, amount in CNY). Tier 0 means no prize.
/// Floating tiers (1 and 2) use conservative long-run estimates.
pub fn prize(game_id: &str, primary_hits: usize, secondary_hits: usize) -> (u8, f64) {
    match game_id {
        "ssq" => match (primary_hits, secondary_hits) {
            (6, 1) => (1, 7_000_000.0),
            (6, 0) => (2, 150_000.0),
            (5, 1) => (3, 3_000.0),
            (5, 0) | (4, 1) => (4, 200.0),
            (4, 0) | (3, 1) => (5, 10.0),
            (_, 1) => (6, 5.0),
            _ => (0, 0.0),
        },
        "dlt" => match (primary_hits, secondary_hits) {
            (5, 2) => (1, 10_000_000.0),
            (5, 1) => (2, 150_000.0),
            (5, 0) => (3, 10_000.0),
            (4, 2) => (4, 3_000.0),
            (4, 1) => (5, 300.0),
            (3, 2) => (6, 200.0),
            (4, 0) => (7, 100.0),
            (3, 1) | (2, 2) => (8, 15.0),
            (3, 0) | (2, 1) | (1, 2) | (0, 2) => (9, 5.0),
            _ => (0, 0.0),
        },
        _ => (0, 0.0),
    }
}

pub fn tier_name(game_id: &str, tier: u8) -> &'static str {
    match game_id {
        "ssq" => match tier {
            1 => "一等奖",
            2 => "二等奖",
            3 => "三等奖",
            4 => "四等奖",
            5 => "五等奖",
            6 => "六等奖",
            _ => "未中奖",
        },
        "dlt" => match tier {
            1 => "一等奖",
            2 => "二等奖",
            3 => "三等奖",
            4 => "四等奖",
            5 => "五等奖",
            6 => "六等奖",
            7 => "七等奖",
            8 => "八等奖",
            9 => "九等奖",
            _ => "未中奖",
        },
        _ => "未中奖",
    }
}
