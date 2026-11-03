//! Prize checking for one hand-picked ticket against a drawn issue.

use serde::Serialize;

use crate::{
    config::{self, GameDef},
    models::Draw,
};

#[derive(Debug, Serialize)]
pub struct Numbers {
    pub primary: Vec<u8>,
    pub secondary: Vec<u8>,
}

#[derive(Debug, Serialize)]
pub struct PrizeCheck {
    pub game: String,
    pub game_name: String,
    pub issue: String,
    pub date: String,
    pub draw: Numbers,
    pub ticket: Numbers,
    pub primary_hits: usize,
    pub secondary_hits: usize,
    pub matched_primary: Vec<u8>,
    pub matched_secondary: Vec<u8>,
    pub tier: u8,
    pub tier_name: &'static str,
    /// Amount in CNY. Tiers 1 and 2 are long-run estimates.
    pub amount: f64,
    pub estimated: bool,
    pub prize_note: &'static str,
    pub cost: f64,
}

/// Matches a ticket against one draw. The caller is responsible for checking
/// that the ticket has the right count, ranges and no duplicates.
pub fn evaluate(draw: &Draw, game: &GameDef, primary: &[u8], secondary: &[u8]) -> PrizeCheck {
    let matched_primary: Vec<u8> = primary
        .iter()
        .copied()
        .filter(|n| draw.contains_primary(*n))
        .collect();
    let matched_secondary: Vec<u8> = secondary
        .iter()
        .copied()
        .filter(|n| draw.contains_secondary(*n))
        .collect();
    let (tier, amount) = config::prize(game.id, matched_primary.len(), matched_secondary.len());
    PrizeCheck {
        game: game.id.to_string(),
        game_name: game.name.to_string(),
        issue: draw.issue.clone(),
        date: draw.date.clone(),
        draw: Numbers {
            primary: draw.primary.clone(),
            secondary: draw.secondary.clone(),
        },
        ticket: Numbers {
            primary: primary.to_vec(),
            secondary: secondary.to_vec(),
        },
        primary_hits: matched_primary.len(),
        secondary_hits: matched_secondary.len(),
        matched_primary,
        matched_secondary,
        tier,
        tier_name: config::tier_name(game.id, tier),
        amount,
        // Both games use floating payouts for the first two tiers only.
        estimated: matches!(tier, 1 | 2),
        prize_note: game.prize_note,
        cost: game.price,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn draw(game: &str, primary: Vec<u8>, secondary: Vec<u8>) -> Draw {
        Draw {
            game: game.into(),
            issue: "test".into(),
            date: "2026-01-01".into(),
            primary,
            secondary,
            sales: None,
            pool: None,
        }
    }

    #[test]
    fn ssq_tiers() {
        let g = config::game("ssq").unwrap();
        let d = draw("ssq", vec![1, 2, 3, 4, 5, 6], vec![7]);
        let cases = [
            (vec![1, 2, 3, 4, 5, 6], vec![7], 1),
            (vec![1, 2, 3, 4, 5, 6], vec![8], 2),
            (vec![1, 2, 3, 4, 5, 9], vec![7], 3),
            (vec![1, 2, 3, 4, 5, 9], vec![8], 4),
            (vec![1, 2, 3, 4, 9, 10], vec![7], 4),
            (vec![1, 2, 3, 4, 9, 10], vec![8], 5),
            (vec![1, 2, 3, 9, 10, 11], vec![7], 5),
            (vec![1, 2, 9, 10, 11, 12], vec![7], 6),
            (vec![9, 10, 11, 12, 13, 14], vec![7], 6),
            (vec![9, 10, 11, 12, 13, 14], vec![8], 0),
        ];
        for (primary, secondary, want) in cases {
            let got = evaluate(&d, g, &primary, &secondary);
            assert_eq!(got.tier, want, "{primary:?} + {secondary:?}");
        }
    }

    #[test]
    fn dlt_tiers() {
        let g = config::game("dlt").unwrap();
        let d = draw("dlt", vec![1, 2, 3, 4, 5], vec![6, 7]);
        let cases = [
            (vec![1, 2, 3, 4, 5], vec![6, 7], 1),
            (vec![1, 2, 3, 4, 5], vec![6, 8], 2),
            (vec![1, 2, 3, 4, 5], vec![8, 9], 3),
            (vec![1, 2, 3, 4, 9], vec![6, 7], 4),
            (vec![1, 2, 3, 4, 9], vec![6, 8], 5),
            (vec![1, 2, 3, 9, 10], vec![6, 7], 6),
            (vec![1, 2, 3, 4, 9], vec![8, 9], 7),
            (vec![1, 2, 3, 9, 10], vec![6, 8], 8),
            (vec![1, 2, 9, 10, 11], vec![6, 7], 8),
            (vec![1, 2, 3, 9, 10], vec![8, 9], 9),
            (vec![1, 2, 9, 10, 11], vec![6, 8], 9),
            (vec![1, 9, 10, 11, 12], vec![6, 7], 9),
            (vec![9, 10, 11, 12, 13], vec![6, 7], 9),
            (vec![1, 2, 9, 10, 11], vec![8, 9], 0),
            (vec![1, 9, 10, 11, 12], vec![8, 9], 0),
        ];
        for (primary, secondary, want) in cases {
            let got = evaluate(&d, g, &primary, &secondary);
            assert_eq!(got.tier, want, "{primary:?} + {secondary:?}");
        }
    }

    #[test]
    fn floating_tiers_are_estimated() {
        let g = config::game("ssq").unwrap();
        let d = draw("ssq", vec![1, 2, 3, 4, 5, 6], vec![7]);
        let first = evaluate(&d, g, &[1, 2, 3, 4, 5, 6], &[7]);
        assert!(first.estimated);
        assert_eq!(first.tier_name, "一等奖");
        let fifth = evaluate(&d, g, &[1, 2, 3, 9, 10, 11], &[7]);
        assert!(!fifth.estimated);
        assert_eq!(fifth.amount, 10.0);
    }

    #[test]
    fn reports_matched_numbers() {
        let g = config::game("dlt").unwrap();
        let d = draw("dlt", vec![1, 2, 3, 4, 5], vec![6, 7]);
        let got = evaluate(&d, g, &[2, 4, 5, 9, 10], &[7, 8]);
        assert_eq!(got.primary_hits, 3);
        assert_eq!(got.secondary_hits, 1);
        assert_eq!(got.matched_primary, vec![2, 4, 5]);
        assert_eq!(got.matched_secondary, vec![7]);
        assert_eq!(got.tier, 8);
        assert_eq!(got.tier_name, "八等奖");
        assert_eq!(got.amount, 15.0);
    }
}
