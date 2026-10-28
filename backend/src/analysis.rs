//! Statistical analysis: frequency, omission, combination features and a
//! battery of randomness tests (with Monte-Carlo calibration).

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use rand::{RngExt, SeedableRng};
use rand_chacha::ChaCha8Rng;
use serde_json::{json, Value};

use crate::config::GameDef;
use crate::models::Draw;
use crate::stats;

#[derive(Debug, Clone)]
pub struct GapStat {
    pub number: usize,
    pub appearances: usize,
    pub current_gap: usize,
    pub max_gap: usize,
    pub avg_gap: f64,
    pub expected_gap: f64,
    pub gaps: Vec<usize>,
}

pub fn number_gaps(draws: &[Draw], max: u8, secondary: bool) -> Vec<GapStat> {
    let mut out = Vec::with_capacity(max as usize);
    for number in 1..=max as usize {
        let mut last: Option<usize> = None;
        let mut gaps = Vec::new();
        let mut appearances = 0usize;
        for (i, d) in draws.iter().enumerate() {
            let present = if secondary {
                d.contains_secondary(number as u8)
            } else {
                d.contains_primary(number as u8)
            };
            if present {
                appearances += 1;
                if let Some(l) = last {
                    gaps.push(i - l - 1);
                }
                last = Some(i);
            }
        }
        let current_gap = match last {
            Some(l) => draws.len().saturating_sub(l + 1),
            None => draws.len(),
        };
        let max_gap = gaps.iter().copied().max().unwrap_or(current_gap);
        let avg_gap = if gaps.is_empty() {
            current_gap as f64
        } else {
            gaps.iter().sum::<usize>() as f64 / gaps.len() as f64
        };
        out.push(GapStat {
            number,
            appearances,
            current_gap,
            max_gap,
            avg_gap,
            expected_gap: 0.0, // filled by caller
            gaps,
        });
    }
    out
}

fn counts_for(draws: &[Draw], max: u8, secondary: bool) -> Vec<usize> {
    let mut counts = vec![0usize; max as usize + 1];
    for d in draws {
        let nums = if secondary {
            &d.secondary
        } else {
            &d.primary
        };
        for &n in nums {
            if n as usize <= max as usize {
                counts[n as usize] += 1;
            }
        }
    }
    counts
}

fn distribution_block(
    draws: &[Draw],
    g: &GameDef,
    secondary: bool,
    window: Option<usize>,
) -> Value {
    let slice = match window {
        Some(w) if w > 0 && w < draws.len() => &draws[draws.len() - w..],
        _ => draws,
    };
    let n = slice.len();
    let (max, k, label) = if secondary {
        (
            g.secondary_max as usize,
            g.secondary_count,
            g.secondary_label,
        )
    } else {
        (g.primary_max as usize, g.primary_count, g.primary_label)
    };
    let counts = counts_for(slice, max as u8, secondary);
    let expected = n as f64 * k as f64 / max as f64;
    let mut chi = 0.0;
    let mut numbers = Vec::with_capacity(max);
    let p_hit = k as f64 / max as f64;
    let sd = (expected * (1.0 - p_hit)).sqrt();
    for number in 1..=max {
        let obs = counts[number] as f64;
        chi += (obs - expected) * (obs - expected) / expected;
    }
    let gaps = number_gaps(slice, max as u8, secondary);
    for stat in gaps {
        let obs = counts[stat.number] as f64;
        let z = if sd > 0.0 { (obs - expected) / sd } else { 0.0 };
        numbers.push(json!({
            "number": stat.number,
            "count": obs as usize,
            "expected": round2(expected),
            "z": round2(z),
            "current_gap": stat.current_gap,
            "max_gap": stat.max_gap,
            "avg_gap": round2(stat.avg_gap),
            "appearance_rate": round4(obs / n.max(1) as f64),
        }));
    }
    let df = max.saturating_sub(1);
    let p = stats::chi_square_sf(chi, df);
    let entropy_bits = stats::entropy(&counts[1..].iter().map(|&c| c as f64).collect::<Vec<_>>());
    let max_entropy = (max as f64).log2();
    json!({
        "label": label,
        "count_per_draw": k,
        "max_number": max,
        "total_draws": n,
        "expected_per_number": round2(expected),
        "chi_square": round2(chi),
        "df": df,
        "p_value": round4(p),
        "entropy_bits": round4(entropy_bits),
        "max_entropy_bits": round4(max_entropy),
        "normalized_entropy": round4(if max_entropy > 0.0 { entropy_bits / max_entropy } else { 0.0 }),
        "numbers": numbers,
    })
}

pub fn frequency(draws: &[Draw], g: &GameDef, window: Option<usize>) -> Value {
    json!({
        "game": g.id,
        "game_name": g.name,
        "window": window.unwrap_or(0),
        "total_draws": draws.len(),
        "primary": distribution_block(draws, g, false, window),
        "secondary": distribution_block(draws, g, true, window),
    })
}

pub fn gaps(draws: &[Draw], g: &GameDef) -> Value {
    let block = |secondary: bool| {
        let (max, k, label) = if secondary {
            (
                g.secondary_max as usize,
                g.secondary_count,
                g.secondary_label,
            )
        } else {
            (g.primary_max as usize, g.primary_count, g.primary_label)
        };
        let mut stats = number_gaps(draws, max as u8, secondary);
        let expected_gap = (max as f64 - k as f64) / k as f64;
        for s in stats.iter_mut() {
            s.expected_gap = expected_gap;
        }
        let items: Vec<Value> = stats
            .iter()
            .map(|s| {
                json!({
                    "number": s.number,
                    "appearances": s.appearances,
                    "current_gap": s.current_gap,
                    "max_gap": s.max_gap,
                    "avg_gap": round2(s.avg_gap),
                    "expected_gap": round2(s.expected_gap),
                })
            })
            .collect();
        json!({ "label": label, "max_number": max, "expected_gap": round2(expected_gap), "numbers": items })
    };
    json!({
        "game": g.id,
        "total_draws": draws.len(),
        "primary": block(false),
        "secondary": block(true),
    })
}

/// Exact distribution of the sum of k distinct numbers drawn from 1..=n.
fn sum_distribution(n: usize, k: usize) -> Vec<f64> {
    let max_sum = k * (2 * n - k + 1) / 2;
    let mut dp = vec![vec![0.0f64; max_sum + 1]; k + 1];
    dp[0][0] = 1.0;
    for v in 1..=n {
        for c in (1..=k).rev() {
            for s in (v..=max_sum).rev() {
                dp[c][s] += dp[c - 1][s - v];
            }
        }
    }
    dp[k].clone()
}

/// Exact distribution of the number of adjacent pairs inside a k-subset of 1..=n.
fn consecutive_distribution(n: usize, k: usize) -> Vec<f64> {
    // dp[chosen][adjacent][last_selected]
    let mut dp = vec![vec![[0.0f64; 2]; k]; k + 1];
    dp[0][0][0] = 1.0;
    for _pos in 1..=n {
        let mut ndp = vec![vec![[0.0f64; 2]; k]; k + 1];
        for c in 0..=k {
            for a in 0..k {
                for last in 0..2 {
                    let v = dp[c][a][last];
                    if v == 0.0 {
                        continue;
                    }
                    // skip
                    ndp[c][a][0] += v;
                    // take
                    if c < k {
                        let na = a + last;
                        if na < k {
                            ndp[c + 1][na][1] += v;
                        }
                    }
                }
            }
        }
        dp = ndp;
    }
    let mut out = vec![0.0; k];
    for c in 0..=k {
        if c != k {
            continue;
        }
        for a in 0..k {
            out[a] += dp[c][a][0] + dp[c][a][1];
        }
    }
    out
}

fn span_distribution(n: usize, k: usize) -> Vec<f64> {
    let mut out = vec![0.0; n];
    if k == 1 {
        out[0] = n as f64;
        return out;
    }
    for span in (k - 1)..n {
        let ways = (n - span) as f64 * stats::combinations(span - 1, k - 2);
        out[span] = ways;
    }
    out
}

fn ac_distribution(n: usize, k: usize) -> Vec<f64> {
    static CACHE: OnceLock<Mutex<HashMap<(usize, usize), Vec<f64>>>> = OnceLock::new();
    let cache = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    if let Some(v) = cache.lock().unwrap().get(&(n, k)) {
        return v.clone();
    }
    let max_ac = (k - 1) * (k - 2) / 2;
    let mut counts = vec![0.0f64; max_ac + 1];
    let mut combo: Vec<usize> = Vec::with_capacity(k);
    fn rec(
        start: usize,
        n: usize,
        k: usize,
        combo: &mut Vec<usize>,
        counts: &mut [f64],
    ) {
        if combo.len() == k {
            let mut diffs = [false; 64];
            for i in 0..combo.len() {
                for j in (i + 1)..combo.len() {
                    let d = combo[j] - combo[i];
                    if d < 64 {
                        diffs[d] = true;
                    }
                }
            }
            let distinct = diffs.iter().filter(|&&b| b).count();
            let ac = distinct.saturating_sub(k - 1);
            if ac < counts.len() {
                counts[ac] += 1.0;
            }
            return;
        }
        let remaining = k - combo.len();
        for v in start..=n {
            if n - v + 1 < remaining {
                break;
            }
            combo.push(v);
            rec(v + 1, n, k, combo, counts);
            combo.pop();
        }
    }
    rec(1, n, k, &mut combo, &mut counts);
    cache
        .lock()
        .unwrap()
        .insert((n, k), counts.clone());
    counts
}

fn sum_of(d: &Draw) -> u32 {
    d.primary.iter().map(|&x| x as u32).sum()
}

fn consecutive_count(nums: &[u8]) -> usize {
    let mut v = nums.to_vec();
    v.sort_unstable();
    v.windows(2).filter(|w| w[1] == w[0] + 1).count()
}

fn ac_value(nums: &[u8]) -> usize {
    let mut set = [false; 64];
    for i in 0..nums.len() {
        for j in (i + 1)..nums.len() {
            let d = (nums[j] as i32 - nums[i] as i32).unsigned_abs() as usize;
            if d < 64 {
                set[d] = true;
            }
        }
    }
    let distinct = set.iter().filter(|&&b| b).count();
    distinct.saturating_sub(nums.len() - 1)
}

fn odd_count(nums: &[u8]) -> usize {
    nums.iter().filter(|&&n| n % 2 == 1).count()
}

fn small_count(nums: &[u8], n: usize) -> usize {
    nums.iter().filter(|&&x| (x as usize) <= n / 2).count()
}

fn binned_block(
    observed: &[f64],
    expected: &[f64],
    labels: &[String],
) -> Value {
    let (chi, df) = stats::chi_square_gof(observed, expected);
    let p = stats::chi_square_sf(chi, df);
    let bins: Vec<Value> = labels
        .iter()
        .enumerate()
        .map(|(i, label)| {
            json!({
                "label": label,
                "observed": observed.get(i).copied().unwrap_or(0.0) as i64,
                "expected": round2(expected.get(i).copied().unwrap_or(0.0)),
            })
        })
        .collect();
    json!({
        "bins": bins,
        "chi_square": round2(chi),
        "df": df,
        "p_value": round4(p),
    })
}

pub fn combinations(draws: &[Draw], g: &GameDef) -> Value {
    let n = g.primary_max as usize;
    let k = g.primary_count;
    let total = draws.len();
    let total_comb = stats::combinations(n, k);

    // ---- sum ----
    let sums: Vec<u32> = draws.iter().map(sum_of).collect();
    let sum_dist = sum_distribution(n, k);
    let min_sum = k * (k + 1) / 2;
    let max_sum = k * (2 * n - k + 1) / 2;
    let bin_width = 10usize;
    let mut sum_obs = vec![0.0; (max_sum - min_sum) / bin_width + 1];
    for &s in &sums {
        let idx = ((s as usize).saturating_sub(min_sum)) / bin_width;
        if idx < sum_obs.len() {
            sum_obs[idx] += 1.0;
        }
    }
    let mut sum_exp = vec![0.0; sum_obs.len()];
    for (s, &ways) in sum_dist.iter().enumerate() {
        if ways > 0.0 {
            let idx = s.saturating_sub(min_sum) / bin_width;
            if idx < sum_exp.len() {
                sum_exp[idx] += ways / total_comb * total as f64;
            }
        }
    }
    let sum_labels: Vec<String> = (0..sum_obs.len())
        .map(|i| format!("{}-{}", min_sum + i * bin_width, min_sum + i * bin_width + bin_width - 1))
        .collect();
    let sum_block = binned_block(&sum_obs, &sum_exp, &sum_labels);
    let obs_mean = stats::mean(&sums.iter().map(|&s| s as f64).collect::<Vec<_>>());
    let obs_sd = stats::std_dev(&sums.iter().map(|&s| s as f64).collect::<Vec<_>>(), true);
    let exp_mean = k as f64 * (n as f64 + 1.0) / 2.0;
    let exp_var = k as f64 * (n as f64 + 1.0) * (n as f64 - k as f64) / 12.0;

    // ---- odd / even ----
    let odd_total = (n + 1) / 2;
    let even_total = n / 2;
    let mut oe_obs = vec![0.0; k + 1];
    for d in draws {
        oe_obs[odd_count(&d.primary)] += 1.0;
    }
    let mut oe_exp = vec![0.0; k + 1];
    let mut oe_labels = Vec::new();
    for o in 0..=k {
        let e = k - o;
        let ways = stats::combinations(odd_total, o) * stats::combinations(even_total, e);
        oe_exp[o] = ways / total_comb * total as f64;
        oe_labels.push(format!("{o}奇{e}偶"));
    }
    let oe_block = binned_block(&oe_obs, &oe_exp, &oe_labels);

    // ---- big / small ----
    let small_total = n / 2;
    let big_total = n - small_total;
    let mut bs_obs = vec![0.0; k + 1];
    for d in draws {
        bs_obs[small_count(&d.primary, n)] += 1.0;
    }
    let mut bs_exp = vec![0.0; k + 1];
    let mut bs_labels = Vec::new();
    for s in 0..=k {
        let b = k - s;
        let ways = stats::combinations(small_total, s) * stats::combinations(big_total, b);
        bs_exp[s] = ways / total_comb * total as f64;
        bs_labels.push(format!("{s}小{b}大"));
    }
    let bs_block = binned_block(&bs_obs, &bs_exp, &bs_labels);

    // ---- consecutive pairs ----
    let cons_dist = consecutive_distribution(n, k);
    let mut cons_obs = vec![0.0; k];
    for d in draws {
        let c = consecutive_count(&d.primary).min(k - 1);
        cons_obs[c] += 1.0;
    }
    let cons_exp: Vec<f64> = cons_dist
        .iter()
        .map(|&ways| ways / total_comb * total as f64)
        .collect();
    let cons_labels: Vec<String> = (0..k).map(|c| format!("{c}组连号")).collect();
    let cons_block = binned_block(&cons_obs, &cons_exp, &cons_labels);

    // ---- span ----
    let span_dist = span_distribution(n, k);
    let span_bin = 5usize;
    let mut span_obs = vec![0.0; (n - 1) / span_bin + 1];
    for d in draws {
        let span = (d.primary.iter().max().unwrap_or(&0) - d.primary.iter().min().unwrap_or(&0)) as usize;
        let idx = span / span_bin;
        if idx < span_obs.len() {
            span_obs[idx] += 1.0;
        }
    }
    let mut span_exp = vec![0.0; span_obs.len()];
    for (span, &ways) in span_dist.iter().enumerate() {
        let idx = span / span_bin;
        if idx < span_exp.len() {
            span_exp[idx] += ways / total_comb * total as f64;
        }
    }
    let span_labels: Vec<String> = (0..span_obs.len())
        .map(|i| format!("{}-{}", i * span_bin, i * span_bin + span_bin - 1))
        .collect();
    let span_block = binned_block(&span_obs, &span_exp, &span_labels);

    // ---- AC value ----
    let ac_dist = ac_distribution(n, k);
    let mut ac_obs = vec![0.0; ac_dist.len()];
    for d in draws {
        let ac = ac_value(&d.primary);
        if ac < ac_obs.len() {
            ac_obs[ac] += 1.0;
        }
    }
    let ac_exp: Vec<f64> = ac_dist
        .iter()
        .map(|&ways| ways / total_comb * total as f64)
        .collect();
    let ac_labels: Vec<String> = (0..ac_dist.len()).map(|i| format!("AC={i}")).collect();
    let ac_block = binned_block(&ac_obs, &ac_exp, &ac_labels);

    let mut sum_block = sum_block;
    if let Some(obj) = sum_block.as_object_mut() {
        obj.insert("mean".into(), json!(round2(obs_mean)));
        obj.insert("expected_mean".into(), json!(round2(exp_mean)));
        obj.insert("sd".into(), json!(round2(obs_sd)));
        obj.insert("expected_sd".into(), json!(round2(exp_var.sqrt())));
    }

    json!({
        "game": g.id,
        "total_draws": total,
        "primary_label": g.primary_label,
        "sum": sum_block,
        "odd_even": oe_block,
        "big_small": bs_block,
        "consecutive": cons_block,
        "span": span_block,
        "ac": ac_block,
    })
}

fn verdict(p: f64) -> &'static str {
    if p < 0.01 {
        "fail"
    } else if p < 0.05 {
        "warn"
    } else {
        "pass"
    }
}

fn sample_distinct(n: usize, k: usize, rng: &mut impl RngExt) -> Vec<u8> {
    let mut pool: Vec<u8> = (1..=n as u8).collect();
    for i in 0..k {
        let j = i + rng.random_range(0..(n - i));
        pool.swap(i, j);
    }
    let mut v = pool[..k].to_vec();
    v.sort_unstable();
    v
}

pub fn randomness(
    draws_all: &[Draw],
    g: &GameDef,
    simulations: usize,
    window: Option<usize>,
) -> Value {
    let draws = match window {
        Some(w) if w > 0 && w < draws_all.len() => &draws_all[draws_all.len() - w..],
        _ => draws_all,
    };
    let total = draws.len();
    let n = g.primary_max as usize;
    let k = g.primary_count;
    let sn = g.secondary_max as usize;
    let sk = g.secondary_count;
    let mut tests: Vec<Value> = Vec::new();

    // 1. marginal uniformity (primary)
    let counts = counts_for(draws, g.primary_max, false);
    let exp = total as f64 * k as f64 / n as f64;
    let chi: f64 = (1..=n)
        .map(|i| {
            let d = counts[i] as f64 - exp;
            d * d / exp
        })
        .sum();
    let p = stats::chi_square_sf(chi, n - 1);
    tests.push(json!({
        "id": "primary_uniformity",
        "name": "红/前区号码均匀性",
        "method": "χ² 拟合优度",
        "statistic": round2(chi),
        "statistic_label": "χ²",
        "p_value": round4(p),
        "verdict": verdict(p),
        "detail": format!("{} 个号码的理论出现次数均为 {:.1} 次，df={}", n, exp, n - 1),
    }));

    // 2. marginal uniformity (secondary)
    let scounts = counts_for(draws, g.secondary_max, true);
    let sexp = total as f64 * sk as f64 / sn as f64;
    let schi: f64 = (1..=sn)
        .map(|i| {
            let d = scounts[i] as f64 - sexp;
            d * d / sexp
        })
        .sum();
    let sp = stats::chi_square_sf(schi, sn - 1);
    tests.push(json!({
        "id": "secondary_uniformity",
        "name": "蓝/后区号码均匀性",
        "method": "χ² 拟合优度",
        "statistic": round2(schi),
        "statistic_label": "χ²",
        "p_value": round4(sp),
        "verdict": verdict(sp),
        "detail": format!("{} 个号码的理论出现次数均为 {:.1} 次，df={}", sn, sexp, sn - 1),
    }));

    // 3. sum distribution vs exact theoretical distribution
    let sum_dist = sum_distribution(n, k);
    let min_sum = k * (k + 1) / 2;
    let max_sum = k * (2 * n - k + 1) / 2;
    let bin_width = 10usize;
    let bins = (max_sum - min_sum) / bin_width + 1;
    let total_comb = stats::combinations(n, k);
    let mut obs = vec![0.0; bins];
    let mut sums = Vec::with_capacity(total);
    for d in draws {
        let s = sum_of(d);
        sums.push(s as f64);
        let idx = ((s as usize).saturating_sub(min_sum)) / bin_width;
        if idx < bins {
            obs[idx] += 1.0;
        }
    }
    let mut expected = vec![0.0; bins];
    for (s, &ways) in sum_dist.iter().enumerate() {
        if ways > 0.0 {
            let idx = s.saturating_sub(min_sum) / bin_width;
            if idx < bins {
                expected[idx] += ways / total_comb * total as f64;
            }
        }
    }
    let (sum_chi, sum_df) = stats::chi_square_gof(&obs, &expected);
    let sum_p = stats::chi_square_sf(sum_chi, sum_df);
    tests.push(json!({
        "id": "sum_distribution",
        "name": "和值分布拟合",
        "method": "χ² 拟合优度（精确组合分布）",
        "statistic": round2(sum_chi),
        "statistic_label": "χ²",
        "p_value": round4(sum_p),
        "verdict": verdict(sum_p),
        "detail": format!("和值按 {} 分箱，df={}", bin_width, sum_df),
    }));

    // 4. mean of sums (z-test)
    let obs_mean = stats::mean(&sums);
    let exp_mean = k as f64 * (n as f64 + 1.0) / 2.0;
    let sum_sd = (k as f64 * (n as f64 + 1.0) * (n as f64 - k as f64) / 12.0).sqrt();
    let se = sum_sd / (total as f64).sqrt();
    let z = if se > 0.0 { (obs_mean - exp_mean) / se } else { 0.0 };
    let mp = stats::normal_two_sided_p(z);
    tests.push(json!({
        "id": "sum_mean",
        "name": "和值均值",
        "method": "单样本 z 检验",
        "statistic": round2(z),
        "statistic_label": "z",
        "p_value": round4(mp),
        "verdict": verdict(mp),
        "detail": format!("观测均值 {:.2}，理论均值 {:.2}，理论标准差 {:.2}", obs_mean, exp_mean, sum_sd),
    }));

    // 5. lag-1 autocorrelation of sums
    let r = stats::pearson(&sums[..total.saturating_sub(1)], &sums[1..]);
    let ap = stats::correlation_p(r, total);
    tests.push(json!({
        "id": "lag1_autocorrelation",
        "name": "和值一阶自相关",
        "method": "Fisher z 变换",
        "statistic": round3(r),
        "statistic_label": "r",
        "p_value": round4(ap),
        "verdict": verdict(ap),
        "detail": "检验相邻两期和值是否线性相关；彩票理论上应为 0。",
    }));

    // 6. runs test on sums above/below median
    let mut sorted_sums = sums.clone();
    sorted_sums.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let median = stats::quantile(&sorted_sums, 0.5);
    let bits: Vec<bool> = sums.iter().map(|&s| s > median).collect();
    let (runs, runs_exp, rz) = stats::runs_test(&bits);
    let rp = stats::normal_two_sided_p(rz);
    tests.push(json!({
        "id": "runs_test",
        "name": "和值游程检验",
        "method": "Wald–Wolfowitz 游程检验",
        "statistic": round2(rz),
        "statistic_label": "z",
        "p_value": round4(rp),
        "verdict": verdict(rp),
        "detail": format!("以中位数 {:.1} 二分，观测游程 {:.0}，期望 {:.1}", median, runs, runs_exp),
    }));

    // 7. consecutive-draw overlap
    let mut overlaps = Vec::with_capacity(total.saturating_sub(1));
    for w in draws.windows(2) {
        let hit = w[1]
            .primary
            .iter()
            .filter(|n| w[0].contains_primary(**n))
            .count();
        overlaps.push(hit as f64);
    }
    let obs_overlap = stats::mean(&overlaps);
    let exp_overlap = k as f64 * k as f64 / n as f64;
    let var_overlap = k as f64
        * (k as f64 / n as f64)
        * (1.0 - k as f64 / n as f64)
        * (n as f64 - k as f64)
        / (n as f64 - 1.0);
    let se_overlap = (var_overlap / overlaps.len().max(1) as f64).sqrt();
    let oz = if se_overlap > 0.0 {
        (obs_overlap - exp_overlap) / se_overlap
    } else {
        0.0
    };
    let op = stats::normal_two_sided_p(oz);
    tests.push(json!({
        "id": "repeat_overlap",
        "name": "相邻两期重号数",
        "method": "超几何分布 z 检验",
        "statistic": round2(oz),
        "statistic_label": "z",
        "p_value": round4(op),
        "verdict": verdict(op),
        "detail": format!("观测均值 {:.3}，理论均值 {:.3}", obs_overlap, exp_overlap),
    }));

    // 8. gap distribution vs geometric
    let gap_stats = number_gaps(draws, g.primary_max, false);
    let p_hit = k as f64 / n as f64;
    let mut gap_obs = vec![0.0; 9];
    let mut gap_total = 0usize;
    for s in &gap_stats {
        for &gap in &s.gaps {
            let idx = match gap {
                0 => 0,
                1 => 1,
                2 => 2,
                3 => 3,
                4 => 4,
                5..=6 => 5,
                7..=9 => 6,
                10..=14 => 7,
                _ => 8,
            };
            gap_obs[idx] += 1.0;
            gap_total += 1;
        }
    }
    let mut gap_exp = vec![0.0; 9];
    for (i, slot) in gap_exp.iter_mut().enumerate() {
        let prob = match i {
            0..=4 => p_hit * (1.0 - p_hit).powi(i as i32),
            5 => p_hit * (1.0 - p_hit).powi(5) * (1.0 + (1.0 - p_hit)),
            6 => p_hit * (1.0 - p_hit).powi(7) * (1.0 + (1.0 - p_hit) + (1.0 - p_hit).powi(2)),
            7 => p_hit
                * (1.0 - p_hit).powi(10)
                * (0..5).map(|j| (1.0 - p_hit).powi(j)).sum::<f64>(),
            _ => (1.0 - p_hit).powi(15),
        };
        *slot = prob * gap_total as f64;
    }
    let (gap_chi, gap_df) = stats::chi_square_gof(&gap_obs, &gap_exp);
    let gap_p = stats::chi_square_sf(gap_chi, gap_df);
    tests.push(json!({
        "id": "gap_geometric",
        "name": "号码间隔分布",
        "method": "χ² 拟合几何分布",
        "statistic": round2(gap_chi),
        "statistic_label": "χ²",
        "p_value": round4(gap_p),
        "verdict": verdict(gap_p),
        "detail": format!("聚合 {} 个号码间隔，df={}", gap_total, gap_df),
    }));

    // 9. entropy (information only)
    let entropy_bits = stats::entropy(&counts[1..].iter().map(|&c| c as f64).collect::<Vec<_>>());
    let max_entropy = (n as f64).log2();
    tests.push(json!({
        "id": "entropy",
        "name": "号码分布熵",
        "method": "Shannon 熵",
        "statistic": round4(entropy_bits),
        "statistic_label": "bits",
        "p_value": Value::Null,
        "verdict": "info",
        "detail": format!("最大熵 {:.3} bits，归一化熵 {:.4}；越接近 1 越接近均匀随机。", max_entropy, entropy_bits / max_entropy),
    }));

    // 10. Monte-Carlo calibration of the primary chi-square statistic
    let sims = simulations.clamp(50, 2000);
    let mut rng = ChaCha8Rng::seed_from_u64(0x5EED_2026);
    let mut ge = 0usize;
    for _ in 0..sims {
        let mut c = vec![0usize; n + 1];
        for _ in 0..total {
            for num in sample_distinct(n, k, &mut rng) {
                c[num as usize] += 1;
            }
        }
        let e = total as f64 * k as f64 / n as f64;
        let sim_chi: f64 = (1..=n)
            .map(|i| {
                let d = c[i] as f64 - e;
                d * d / e
            })
            .sum();
        if sim_chi >= chi {
            ge += 1;
        }
    }
    let mc_p = (ge as f64 + 1.0) / (sims as f64 + 1.0);
    tests.push(json!({
        "id": "monte_carlo",
        "name": "蒙特卡洛校准",
        "method": "模拟相同期数的随机开奖",
        "statistic": round2(chi),
        "statistic_label": "χ²",
        "p_value": round4(mc_p),
        "verdict": verdict(mc_p),
        "detail": format!("{} 次模拟中，{:.1}% 的随机数据集 χ² 不低于真实数据；p≈{:.4}", sims, ge as f64 / sims as f64 * 100.0, mc_p),
    }));

    let p_values: Vec<f64> = tests
        .iter()
        .filter_map(|t| t.get("p_value").and_then(|v| v.as_f64()))
        .collect();
    let significant = p_values.iter().filter(|&&p| p < 0.05).count();
    let expected_false = p_values.len() as f64 * 0.05;
    // Probability of seeing at least this many p<0.05 results when all null
    // hypotheses are true. This is the multiple-comparison-corrected verdict.
    let overall_p = stats::binomial_tail(p_values.len(), significant, 0.05);
    let overall_verdict = verdict(overall_p);
    let conclusion = if significant == 0 {
        format!(
            "{} 项检验全部未达到 p<0.05，整体多重比较 p={:.3}。数据与独立均匀随机假设一致，未发现可用于预测的统计规律。",
            p_values.len(),
            overall_p
        )
    } else if overall_p >= 0.05 {
        format!(
            "{} 项检验中有 {} 项 p<0.05，但整体多重比较 p={:.3}，与纯随机情况下“至少出现这么多显著项”的概率相当（期望约 {:.2} 项）。不构成系统性偏离，也没有预测价值。",
            p_values.len(),
            significant,
            overall_p,
            expected_false
        )
    } else {
        format!(
            "{} 项检验中有 {} 项 p<0.05，整体多重比较 p={:.4}，显著多于随机预期（约 {:.2} 项）。这可能是历史规则/设备变更或数据问题，建议切换窗口复核；即使真实存在偏差，也需通过样本外回测确认能否转化为收益。",
            p_values.len(),
            significant,
            overall_p,
            expected_false
        )
    };

    json!({
        "game": g.id,
        "game_name": g.name,
        "total_draws": total,
        "window": window.unwrap_or(0),
        "simulations": sims,
        "tests": tests,
        "significant_count": significant,
        "test_count": p_values.len(),
        "expected_false_positives": round2(expected_false),
        "overall_p": round4(overall_p),
        "overall_verdict": overall_verdict,
        "conclusion": conclusion,
        "note": "彩票开奖规则或摇奖设备在历史上可能变更（例如大乐透 2014 年前后的号码分布差异）。若分析窗口跨越变更点，整体检验可能不满足同分布假设，建议同时查看最近 300–500 期的结果。"
    })
}

pub fn round2(x: f64) -> f64 {
    (x * 100.0).round() / 100.0
}

pub fn round3(x: f64) -> f64 {
    (x * 1000.0).round() / 1000.0
}

pub fn round4(x: f64) -> f64 {
    (x * 10000.0).round() / 10000.0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn draw(primary: &[u8], secondary: &[u8]) -> Draw {
        Draw {
            game: "ssq".into(),
            issue: "1".into(),
            date: "2020-01-01".into(),
            primary: primary.to_vec(),
            secondary: secondary.to_vec(),
            sales: None,
            pool: None,
        }
    }

    #[test]
    fn sum_distribution_totals_to_combination_count() {
        let dist = sum_distribution(33, 6);
        let total: f64 = dist.iter().sum();
        assert!((total - stats::combinations(33, 6)).abs() < 1.0);
    }

    #[test]
    fn consecutive_distribution_totals() {
        let dist = consecutive_distribution(33, 6);
        let total: f64 = dist.iter().sum();
        assert!((total - stats::combinations(33, 6)).abs() < 1.0);
    }

    #[test]
    fn span_distribution_totals() {
        let dist = span_distribution(33, 6);
        let total: f64 = dist.iter().sum();
        assert!((total - stats::combinations(33, 6)).abs() < 1.0);
    }

    #[test]
    fn ac_distribution_totals() {
        let dist = ac_distribution(33, 6);
        let total: f64 = dist.iter().sum();
        assert!((total - stats::combinations(33, 6)).abs() < 1.0);
    }

    #[test]
    fn ac_of_arithmetic_progression() {
        assert_eq!(ac_value(&[1, 2, 3, 4, 5, 6]), 0);
        assert_eq!(ac_value(&[1, 2, 4, 8, 16, 32]), 10);
    }

    #[test]
    fn gap_stats_count_omissions() {
        let draws = vec![
            draw(&[1, 2, 3, 4, 5, 6], &[1]),
            draw(&[1, 2, 3, 4, 5, 7], &[2]),
            draw(&[1, 2, 3, 4, 5, 8], &[3]),
        ];
        let stats = number_gaps(&draws, 33, false);
        assert_eq!(stats[0].number, 1);
        assert_eq!(stats[0].current_gap, 0);
        assert_eq!(stats[5].current_gap, 2);
    }
}
