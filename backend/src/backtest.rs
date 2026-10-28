//! Strict walk-forward backtesting. At every step the strategy only sees the
//! draws that happened before the draw being scored.

use anyhow::{bail, Result};
use rand::{RngExt, SeedableRng};
use rand_chacha::ChaCha8Rng;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::config::{self, GameDef};
use crate::models::Draw;
use crate::stats;
use crate::strategies::{StrategyKind, StrategyRunner};

#[derive(Debug, Clone, Deserialize)]
pub struct BacktestRequest {
    pub game: String,
    #[serde(default)]
    pub strategies: Option<Vec<String>>,
    #[serde(default)]
    pub train_window: Option<usize>,
    #[serde(default)]
    pub test_size: Option<usize>,
    #[serde(default)]
    pub tickets_per_draw: Option<usize>,
    #[serde(default)]
    pub seed: Option<u64>,
}

pub fn run(draws: &[Draw], g: &GameDef, req: &BacktestRequest) -> Result<Value> {
    if draws.len() < 60 {
        bail!("历史数据太少（当前 {} 期），至少需要 60 期", draws.len());
    }
    let test_size = req
        .test_size
        .unwrap_or(300)
        .clamp(20, draws.len().saturating_sub(30));
    let test_start = draws.len() - test_size;
    let train_window = req
        .train_window
        .unwrap_or(500)
        .clamp(30, test_start.max(30));
    let tickets_per_draw = req.tickets_per_draw.unwrap_or(1).clamp(1, 20);
    let seed = req.seed.unwrap_or(42);
    let kinds: Vec<StrategyKind> = match &req.strategies {
        Some(ids) if !ids.is_empty() => ids
            .iter()
            .filter_map(|s| StrategyKind::from_id(s))
            .collect(),
        _ => StrategyKind::all().to_vec(),
    };
    if kinds.is_empty() {
        bail!("没有可识别的策略");
    }

    let n = g.primary_max as usize;
    let k = g.primary_count;
    let sn = g.secondary_max as usize;
    let sk = g.secondary_count;
    let price = g.price;
    let p_hit = k as f64 / n as f64;
    let sp_hit = sk as f64 / sn as f64;
    let var_hits = k as f64 * p_hit * (1.0 - p_hit) * (n as f64 - k as f64) / (n as f64 - 1.0);
    let var_shits = sk as f64 * sp_hit * (1.0 - sp_hit) * (sn as f64 - sk as f64) / (sn as f64 - 1.0);
    let expected_hits = k as f64 * p_hit;
    let expected_shits = sk as f64 * sp_hit;
    let uniform_brier =
        (k as f64 * (1.0 - p_hit).powi(2) + (n - k) as f64 * p_hit.powi(2)) / n as f64;
    let uniform_brier_s =
        (sk as f64 * (1.0 - sp_hit).powi(2) + (sn - sk) as f64 * sp_hit.powi(2)) / sn as f64;

    let mut results = Vec::new();
    for (idx, kind) in kinds.iter().enumerate() {
        let mut runner = StrategyRunner::new(
            *kind,
            *g,
            &draws[test_start.saturating_sub(train_window)..test_start],
            seed.wrapping_add(idx as u64 * 7919),
        );
        let mut tickets = 0usize;
        let mut cost = 0.0f64;
        let mut payout = 0.0f64;
        let mut hits_sum = 0usize;
        let mut shits_sum = 0usize;
        let mut brier_sum = 0.0f64;
        let mut brier_n = 0usize;
        let mut sbrier_sum = 0.0f64;
        let mut sbrier_n = 0usize;
        let mut tier_counts = vec![0usize; 10];
        let mut hit_dist = vec![0usize; k + 1];
        let mut s_hit_dist = vec![0usize; sk + 1];
        let mut per_draw_net = Vec::with_capacity(test_size);
        let mut cumulative = Vec::with_capacity(test_size);
        let mut cum = 0.0f64;
        let mut wins = 0usize;

        for t in test_start..draws.len() {
            let history = &draws[..t];
            let actual = &draws[t];
            let mut draw_cost = 0.0f64;
            let mut draw_payout = 0.0f64;
            for _ in 0..tickets_per_draw {
                let pred = runner.predict(history);
                let hits = pred
                    .primary
                    .iter()
                    .filter(|&&x| actual.contains_primary(x))
                    .count();
                let shits = pred
                    .secondary
                    .iter()
                    .filter(|&&x| actual.contains_secondary(x))
                    .count();
                let (tier, amount) = config::prize(g.id, hits, shits);
                tickets += 1;
                cost += price;
                payout += amount;
                draw_cost += price;
                draw_payout += amount;
                hits_sum += hits;
                shits_sum += shits;
                tier_counts[tier as usize] += 1;
                hit_dist[hits.min(k)] += 1;
                s_hit_dist[shits.min(sk)] += 1;
                if amount > 0.0 {
                    wins += 1;
                }
                for num in 1..=n {
                    let p = pred
                        .primary_probs
                        .get(num)
                        .copied()
                        .unwrap_or(0.0)
                        .clamp(0.0, 1.0);
                    let y = actual.contains_primary(num as u8) as u8 as f64;
                    brier_sum += (p - y) * (p - y);
                    brier_n += 1;
                }
                for num in 1..=sn {
                    let p = pred
                        .secondary_probs
                        .get(num)
                        .copied()
                        .unwrap_or(0.0)
                        .clamp(0.0, 1.0);
                    let y = actual.contains_secondary(num as u8) as u8 as f64;
                    sbrier_sum += (p - y) * (p - y);
                    sbrier_n += 1;
                }
            }
            let net = draw_payout - draw_cost;
            per_draw_net.push(net);
            cum += net;
            cumulative.push(json!({
                "i": t - test_start + 1,
                "issue": actual.issue,
                "date": actual.date,
                "net": round2(net),
                "cumulative": round2(cum),
            }));
            runner.observe(actual);
        }

        let mean_hits = hits_sum as f64 / tickets.max(1) as f64;
        let mean_shits = shits_sum as f64 / tickets.max(1) as f64;
        let z = if tickets > 0 && var_hits > 0.0 {
            (mean_hits - expected_hits) / (var_hits / tickets as f64).sqrt()
        } else {
            0.0
        };
        let sz = if tickets > 0 && var_shits > 0.0 {
            (mean_shits - expected_shits) / (var_shits / tickets as f64).sqrt()
        } else {
            0.0
        };
        let p = stats::normal_two_sided_p(z);
        let sp = stats::normal_two_sided_p(sz);
        let roi = if cost > 0.0 { (payout - cost) / cost } else { 0.0 };
        let (ci_lo, ci_hi) = bootstrap_roi(&per_draw_net, price, seed ^ 0xA5A5_1234);
        let tiers: Vec<Value> = (0..=9)
            .filter(|&t| tier_counts[t] > 0)
            .map(|t| {
                json!({
                    "tier": t,
                    "name": config::tier_name(g.id, t as u8),
                    "count": tier_counts[t],
                })
            })
            .collect();
        let hit_distribution: Vec<Value> = (0..=k)
            .map(|h| json!({ "hits": h, "count": hit_dist[h] }))
            .collect();

        results.push(json!({
            "strategy": kind.id(),
            "label": kind.label(),
            "description": kind.description(),
            "degenerate_probs": matches!(
                kind,
                StrategyKind::Hot | StrategyKind::Cold | StrategyKind::Overdue | StrategyKind::Balanced
            ),
            "tickets": tickets,
            "cost": round2(cost),
            "payout": round2(payout),
            "profit": round2(payout - cost),
            "roi": round4(roi),
            "roi_ci": [round4(ci_lo), round4(ci_hi)],
            "win_tickets": wins,
            "avg_primary_hits": round4(mean_hits),
            "expected_primary_hits": round4(expected_hits),
            "primary_z": round2(z),
            "p_value": round4(p),
            "avg_secondary_hits": round4(mean_shits),
            "expected_secondary_hits": round4(expected_shits),
            "secondary_z": round2(sz),
            "secondary_p_value": round4(sp),
            "brier": round4(brier_sum / brier_n.max(1) as f64),
            "uniform_brier": round4(uniform_brier),
            "secondary_brier": round4(sbrier_sum / sbrier_n.max(1) as f64),
            "uniform_secondary_brier": round4(uniform_brier_s),
            "hit_distribution": hit_distribution,
            "secondary_hit_distribution": (0..=sk).map(|h| json!({"hits": h, "count": s_hit_dist[h]})).collect::<Vec<_>>(),
            "tier_counts": tiers,
            "cumulative": cumulative,
        }));
    }

    let significant = results
        .iter()
        .filter(|r| r.get("p_value").and_then(|v| v.as_f64()).unwrap_or(1.0) < 0.05)
        .count();
    let overall_p = stats::binomial_tail(results.len(), significant, 0.05);
    let overall_verdict = if overall_p < 0.01 {
        "fail"
    } else if overall_p < 0.05 {
        "warn"
    } else {
        "pass"
    };
    let best = results
        .iter()
        .max_by(|a, b| {
            let ra = a.get("roi").and_then(|v| v.as_f64()).unwrap_or(f64::MIN);
            let rb = b.get("roi").and_then(|v| v.as_f64()).unwrap_or(f64::MIN);
            ra.partial_cmp(&rb).unwrap()
        })
        .and_then(|r| r.get("label"))
        .and_then(|v| v.as_str())
        .unwrap_or("-");
    let verdict = if significant == 0 {
        format!(
            "在 {} 个策略、{} 期走查回测中，没有任何策略的命中率显著高于随机基线（p<0.05）。这正是独立随机开奖应有的结果。",
            results.len(),
            test_size
        )
    } else {
        format!(
            "{} 个策略中有 {} 个 p<0.05。注意这是多重比较：随机情况下也会有约 {:.2} 个策略“显著”。应结合样本外验证与效应量判断，不能据此认为存在预测能力。",
            results.len(),
            significant,
            results.len() as f64 * 0.05
        )
    };

    Ok(json!({
        "game": g.id,
        "game_name": g.name,
        "train_window": train_window,
        "test_size": test_size,
        "test_start_issue": draws[test_start].issue,
        "test_end_issue": draws[draws.len() - 1].issue,
        "tickets_per_draw": tickets_per_draw,
        "ticket_price": price,
        "prize_note": g.prize_note,
        "best_roi_strategy": best,
        "significant_count": significant,
        "overall_p": round4(overall_p),
        "overall_verdict": overall_verdict,
        "results": results,
        "verdict": verdict,
    }))
}

fn bootstrap_roi(nets: &[f64], price: f64, seed: u64) -> (f64, f64) {
    if nets.is_empty() {
        return (0.0, 0.0);
    }
    let mut rng = ChaCha8Rng::seed_from_u64(seed);
    let mut rois = Vec::with_capacity(1000);
    for _ in 0..1000 {
        let mut payout = 0.0;
        for _ in 0..nets.len() {
            let idx = rng.random_range(0..nets.len());
            payout += nets[idx];
        }
        let cost = price * nets.len() as f64;
        rois.push(if cost > 0.0 { payout / cost - 1.0 } else { 0.0 });
    }
    rois.sort_by(|a, b| a.partial_cmp(b).unwrap());
    (
        stats::quantile(&rois, 0.025),
        stats::quantile(&rois, 0.975),
    )
}

fn round2(x: f64) -> f64 {
    (x * 100.0).round() / 100.0
}

fn round4(x: f64) -> f64 {
    (x * 10000.0).round() / 10000.0
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strategies::sample_distinct_for_test;

    fn synthetic(g: &GameDef, count: usize) -> Vec<Draw> {
        let mut rng = ChaCha8Rng::seed_from_u64(11);
        (0..count)
            .map(|i| Draw {
                game: g.id.into(),
                issue: format!("{:07}", i),
                date: format!("2020-{:02}-{:02}", (i % 12) + 1, (i % 28) + 1),
                primary: sample_distinct_for_test(g.primary_max as usize, g.primary_count, &mut rng),
                secondary: sample_distinct_for_test(
                    g.secondary_max as usize,
                    g.secondary_count,
                    &mut rng,
                ),
                sales: None,
                pool: None,
            })
            .collect()
    }

    #[test]
    fn random_strategy_has_no_edge() {
        let g = config::game("ssq").unwrap();
        let draws = synthetic(g, 400);
        let req = BacktestRequest {
            game: "ssq".into(),
            strategies: Some(vec!["random".into()]),
            train_window: Some(100),
            test_size: Some(200),
            tickets_per_draw: Some(2),
            seed: Some(1),
        };
        let v = run(&draws, g, &req).unwrap();
        let r = &v["results"][0];
        assert_eq!(r["tickets"], 400);
        assert!(r["roi"].as_f64().unwrap() < 0.5);
    }
}
