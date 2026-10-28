//! Candidate selection strategies used both for ticket generation and for
//! walk-forward backtesting. Every strategy only ever sees data available
//! *before* the draw it is predicting.

use rand::{RngExt, SeedableRng};
use rand_chacha::ChaCha8Rng;

use crate::config::GameDef;
use crate::models::{Draw, Prediction};
use crate::stats;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StrategyKind {
    Random,
    Hot,
    Cold,
    Overdue,
    Weighted,
    Markov,
    Logistic,
    Balanced,
}

impl StrategyKind {
    pub fn all() -> [StrategyKind; 8] {
        [
            StrategyKind::Random,
            StrategyKind::Hot,
            StrategyKind::Cold,
            StrategyKind::Overdue,
            StrategyKind::Weighted,
            StrategyKind::Markov,
            StrategyKind::Logistic,
            StrategyKind::Balanced,
        ]
    }

    pub fn from_id(id: &str) -> Option<Self> {
        Some(match id {
            "random" => Self::Random,
            "hot" => Self::Hot,
            "cold" => Self::Cold,
            "overdue" => Self::Overdue,
            "weighted" => Self::Weighted,
            "markov" => Self::Markov,
            "logistic" => Self::Logistic,
            "balanced" => Self::Balanced,
            _ => return None,
        })
    }

    pub fn id(&self) -> &'static str {
        match self {
            Self::Random => "random",
            Self::Hot => "hot",
            Self::Cold => "cold",
            Self::Overdue => "overdue",
            Self::Weighted => "weighted",
            Self::Markov => "markov",
            Self::Logistic => "logistic",
            Self::Balanced => "balanced",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::Random => "随机基线",
            Self::Hot => "热号策略",
            Self::Cold => "冷号策略",
            Self::Overdue => "遗漏回补",
            Self::Weighted => "频率加权",
            Self::Markov => "共现马尔可夫",
            Self::Logistic => "在线逻辑回归",
            Self::Balanced => "结构均衡选号",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            Self::Random => "均匀随机抽取，作为检验其他策略是否有效的理论基线。",
            Self::Hot => "选取最近 100 期内出现次数最多的号码，检验“热号延续”是否存在。",
            Self::Cold => "选取最近 100 期内出现次数最少的号码，检验“冷号回补”是否存在。",
            Self::Overdue => "选取当前遗漏期数最大的号码，检验“该出了”的赌徒谬误。",
            Self::Weighted => "按近期频率平滑加权后无放回抽样，属于软性热号策略。",
            Self::Markov => "用历史共现关系计算条件概率增量，检验号码之间是否存在联动。",
            Self::Logistic => "对每个号码做在线逻辑回归（近 10/30/100 期频率、遗漏、上期是否出现），按预测概率抽样。",
            Self::Balanced => "随机生成后只保留和值、奇偶、跨度处于历史常见区间的组合，让号码“看起来正常”。",
        }
    }
}

#[derive(Debug, Clone)]
struct BalancedCfg {
    sum_lo: f64,
    sum_hi: f64,
    odd_lo: usize,
    odd_hi: usize,
    span_lo: u8,
}

#[derive(Debug, Clone)]
struct Logistic {
    primary: Vec<[f64; 7]>,
    secondary: Vec<[f64; 7]>,
}

impl Logistic {
    fn new(g: &GameDef) -> Self {
        Self {
            primary: vec![[0.0; 7]; g.primary_max as usize + 1],
            secondary: vec![[0.0; 7]; g.secondary_max as usize + 1],
        }
    }

    fn sigmoid(z: f64) -> f64 {
        1.0 / (1.0 + (-z).exp())
    }

    fn train(&mut self, history: &[Draw], g: &GameDef, epochs: usize) {
        if history.len() < 20 {
            return;
        }
        let start = history.len().saturating_sub(300);
        for _ in 0..epochs {
            for t in (start + 1)..history.len() {
                let h = &history[..t];
                let actual = &history[t];
                for num in 1..=g.primary_max {
                    let x = primary_features(h, g, num);
                    let z: f64 = self.primary[num as usize]
                        .iter()
                        .zip(x.iter())
                        .map(|(w, v)| w * v)
                        .sum();
                    let p = Self::sigmoid(z);
                    let y = actual.contains_primary(num) as u8 as f64;
                    let err = y - p;
                    for j in 0..7 {
                        self.primary[num as usize][j] += 0.12 * err * x[j];
                    }
                }
                for num in 1..=g.secondary_max {
                    let x = secondary_features(h, g, num);
                    let z: f64 = self.secondary[num as usize]
                        .iter()
                        .zip(x.iter())
                        .map(|(w, v)| w * v)
                        .sum();
                    let p = Self::sigmoid(z);
                    let y = actual.contains_secondary(num) as u8 as f64;
                    let err = y - p;
                    for j in 0..7 {
                        self.secondary[num as usize][j] += 0.12 * err * x[j];
                    }
                }
            }
        }
    }

    fn probs(&self, history: &[Draw], g: &GameDef) -> (Vec<f64>, Vec<f64>, Vec<[f64; 7]>, Vec<[f64; 7]>) {
        let mut pv = vec![0.0; g.primary_max as usize + 1];
        let mut sv = vec![0.0; g.secondary_max as usize + 1];
        let mut pf = Vec::with_capacity(g.primary_max as usize + 1);
        let mut sf = Vec::with_capacity(g.secondary_max as usize + 1);
        pf.push([0.0; 7]);
        sf.push([0.0; 7]);
        for num in 1..=g.primary_max {
            let x = primary_features(history, g, num);
            let z: f64 = self.primary[num as usize]
                .iter()
                .zip(x.iter())
                .map(|(w, v)| w * v)
                .sum();
            pv[num as usize] = Self::sigmoid(z);
            pf.push(x);
        }
        for num in 1..=g.secondary_max {
            let x = secondary_features(history, g, num);
            let z: f64 = self.secondary[num as usize]
                .iter()
                .zip(x.iter())
                .map(|(w, v)| w * v)
                .sum();
            sv[num as usize] = Self::sigmoid(z);
            sf.push(x);
        }
        (pv, sv, pf, sf)
    }

    fn observe(
        &mut self,
        actual: &Draw,
        pf: &[[f64; 7]],
        sf: &[[f64; 7]],
        g: &GameDef,
    ) {
        for num in 1..=g.primary_max {
            let p = {
                let x = &pf[num as usize];
                let z: f64 = self.primary[num as usize]
                    .iter()
                    .zip(x.iter())
                    .map(|(w, v)| w * v)
                    .sum();
                Self::sigmoid(z)
            };
            let y = actual.contains_primary(num) as u8 as f64;
            let err = y - p;
            for j in 0..7 {
                self.primary[num as usize][j] += 0.05 * err * pf[num as usize][j];
            }
        }
        for num in 1..=g.secondary_max {
            let p = {
                let x = &sf[num as usize];
                let z: f64 = self.secondary[num as usize]
                    .iter()
                    .zip(x.iter())
                    .map(|(w, v)| w * v)
                    .sum();
                Self::sigmoid(z)
            };
            let y = actual.contains_secondary(num) as u8 as f64;
            let err = y - p;
            for j in 0..7 {
                self.secondary[num as usize][j] += 0.05 * err * sf[num as usize][j];
            }
        }
    }
}

fn primary_features(history: &[Draw], g: &GameDef, number: u8) -> [f64; 7] {
    let freq = |w: usize| {
        let slice = &history[history.len().saturating_sub(w)..];
        if slice.is_empty() {
            return 0.0;
        }
        slice.iter().filter(|d| d.contains_primary(number)).count() as f64 / slice.len() as f64
    };
    let gap = history
        .iter()
        .rev()
        .position(|d| d.contains_primary(number))
        .map(|p| p as f64)
        .unwrap_or(history.len() as f64);
    let last = history
        .last()
        .map(|d| d.contains_primary(number) as u8 as f64)
        .unwrap_or(0.0);
    [
        1.0,
        freq(10),
        freq(30),
        freq(100),
        (gap / 20.0).min(2.0),
        last,
        number as f64 / g.primary_max as f64,
    ]
}

fn secondary_features(history: &[Draw], g: &GameDef, number: u8) -> [f64; 7] {
    let freq = |w: usize| {
        let slice = &history[history.len().saturating_sub(w)..];
        if slice.is_empty() {
            return 0.0;
        }
        slice.iter().filter(|d| d.contains_secondary(number)).count() as f64 / slice.len() as f64
    };
    let gap = history
        .iter()
        .rev()
        .position(|d| d.contains_secondary(number))
        .map(|p| p as f64)
        .unwrap_or(history.len() as f64);
    let last = history
        .last()
        .map(|d| d.contains_secondary(number) as u8 as f64)
        .unwrap_or(0.0);
    [
        1.0,
        freq(10),
        freq(30),
        freq(100),
        (gap / 20.0).min(2.0),
        last,
        number as f64 / g.secondary_max as f64,
    ]
}

pub struct StrategyRunner {
    pub kind: StrategyKind,
    game: GameDef,
    rng: ChaCha8Rng,
    balanced: Option<BalancedCfg>,
    logistic: Option<Logistic>,
    last_pf: Vec<[f64; 7]>,
    last_sf: Vec<[f64; 7]>,
}

impl StrategyRunner {
    pub fn new(kind: StrategyKind, g: GameDef, initial: &[Draw], seed: u64) -> Self {
        let balanced = if kind == StrategyKind::Balanced {
            Some(balanced_cfg(initial, &g))
        } else {
            None
        };
        let logistic = if kind == StrategyKind::Logistic {
            let mut m = Logistic::new(&g);
            m.train(initial, &g, 2);
            Some(m)
        } else {
            None
        };
        Self {
            kind,
            game: g,
            rng: ChaCha8Rng::seed_from_u64(seed),
            balanced,
            logistic,
            last_pf: Vec::new(),
            last_sf: Vec::new(),
        }
    }

    pub fn predict(&mut self, history: &[Draw]) -> Prediction {
        self.predict_variant(history, 0)
    }

    /// `variant` rotates the candidate window for deterministic ranking
    /// strategies so that generating several tickets yields distinct picks.
    /// Non-deterministic strategies ignore it (their RNG advances instead).
    pub fn predict_variant(&mut self, history: &[Draw], variant: usize) -> Prediction {
        let g = self.game;
        match self.kind {
            StrategyKind::Random => self.random(history),
            StrategyKind::Hot => self.frequency_rank(history, true, variant),
            StrategyKind::Cold => self.frequency_rank(history, false, variant),
            StrategyKind::Overdue => self.overdue(history, variant),
            StrategyKind::Weighted => self.weighted(history),
            StrategyKind::Markov => self.markov(history),
            StrategyKind::Logistic => self.logistic(history),
            StrategyKind::Balanced => self.balanced(history),
        }
        .with_game(&g)
    }

    pub fn observe(&mut self, actual: &Draw) {
        if self.kind == StrategyKind::Logistic {
            if let Some(model) = self.logistic.as_mut() {
                model.observe(actual, &self.last_pf, &self.last_sf, &self.game);
            }
        }
    }

    fn sample_primary(&mut self) -> Vec<u8> {
        sample_distinct(self.game.primary_max as usize, self.game.primary_count, &mut self.rng)
    }

    fn sample_secondary(&mut self) -> Vec<u8> {
        sample_distinct(
            self.game.secondary_max as usize,
            self.game.secondary_count,
            &mut self.rng,
        )
    }

    fn random(&mut self, _history: &[Draw]) -> Prediction {
        let primary = self.sample_primary();
        let secondary = self.sample_secondary();
        let n = self.game.primary_max as usize;
        let k = self.game.primary_count;
        let sn = self.game.secondary_max as usize;
        let sk = self.game.secondary_count;
        let mut primary_probs = vec![k as f64 / n as f64; n + 1];
        primary_probs[0] = 0.0;
        let mut secondary_probs = vec![sk as f64 / sn as f64; sn + 1];
        secondary_probs[0] = 0.0;
        Prediction {
            primary,
            secondary,
            primary_probs,
            secondary_probs,
        }
    }

    fn frequency_rank(&mut self, history: &[Draw], hot: bool, variant: usize) -> Prediction {
        let g = self.game;
        let slice = &history[history.len().saturating_sub(100)..];
        let mut counts = vec![(0usize, 0u8); g.primary_max as usize + 1];
        for num in 1..=g.primary_max {
            let c = slice.iter().filter(|d| d.contains_primary(num)).count();
            counts[num as usize] = (c, num);
        }
        let mut ranked: Vec<(usize, u8)> = counts[1..].to_vec();
        if hot {
            ranked.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
        } else {
            ranked.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
        }
        let offset = variant % ranked.len().saturating_sub(g.primary_count).max(1);
        let mut primary: Vec<u8> = ranked
            .iter()
            .skip(offset)
            .take(g.primary_count)
            .map(|&(_, n)| n)
            .collect();
        primary.sort_unstable();

        let mut scounts = vec![(0usize, 0u8); g.secondary_max as usize + 1];
        for num in 1..=g.secondary_max {
            let c = slice.iter().filter(|d| d.contains_secondary(num)).count();
            scounts[num as usize] = (c, num);
        }
        let mut sranked: Vec<(usize, u8)> = scounts[1..].to_vec();
        if hot {
            sranked.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
        } else {
            sranked.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
        }
        let soffset = variant % sranked.len().saturating_sub(g.secondary_count).max(1);
        let mut secondary: Vec<u8> = sranked
            .iter()
            .skip(soffset)
            .take(g.secondary_count)
            .map(|&(_, n)| n)
            .collect();
        secondary.sort_unstable();
        let (pp, sp) = degenerate_probs(&g, &primary, &secondary);
        Prediction {
            primary,
            secondary,
            primary_probs: pp,
            secondary_probs: sp,
        }
    }

    fn overdue(&mut self, history: &[Draw], variant: usize) -> Prediction {
        let g = self.game;
        let mut gaps = vec![(0usize, 0u8); g.primary_max as usize + 1];
        for num in 1..=g.primary_max {
            let gap = history
                .iter()
                .rev()
                .position(|d| d.contains_primary(num))
                .map(|p| p)
                .unwrap_or(history.len());
            gaps[num as usize] = (gap, num);
        }
        let mut ranked: Vec<(usize, u8)> = gaps[1..].to_vec();
        ranked.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
        let offset = variant % ranked.len().saturating_sub(g.primary_count).max(1);
        let mut primary: Vec<u8> = ranked
            .iter()
            .skip(offset)
            .take(g.primary_count)
            .map(|&(_, n)| n)
            .collect();
        primary.sort_unstable();

        let mut sgaps = vec![(0usize, 0u8); g.secondary_max as usize + 1];
        for num in 1..=g.secondary_max {
            let gap = history
                .iter()
                .rev()
                .position(|d| d.contains_secondary(num))
                .map(|p| p)
                .unwrap_or(history.len());
            sgaps[num as usize] = (gap, num);
        }
        let mut sranked: Vec<(usize, u8)> = sgaps[1..].to_vec();
        sranked.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
        let soffset = variant % sranked.len().saturating_sub(g.secondary_count).max(1);
        let mut secondary: Vec<u8> = sranked
            .iter()
            .skip(soffset)
            .take(g.secondary_count)
            .map(|&(_, n)| n)
            .collect();
        secondary.sort_unstable();
        let (pp, sp) = degenerate_probs(&g, &primary, &secondary);
        Prediction {
            primary,
            secondary,
            primary_probs: pp,
            secondary_probs: sp,
        }
    }

    fn weighted(&mut self, history: &[Draw]) -> Prediction {
        let g = self.game;
        let slice = &history[history.len().saturating_sub(100)..];
        let mut wp = vec![0.0f64; g.primary_max as usize + 1];
        for num in 1..=g.primary_max {
            let c = slice.iter().filter(|d| d.contains_primary(num)).count();
            wp[num as usize] = c as f64 + 1.0;
        }
        let primary = weighted_sample(&wp, g.primary_count, &mut self.rng);
        let mut ws = vec![0.0f64; g.secondary_max as usize + 1];
        for num in 1..=g.secondary_max {
            let c = slice.iter().filter(|d| d.contains_secondary(num)).count();
            ws[num as usize] = c as f64 + 1.0;
        }
        let secondary = weighted_sample(&ws, g.secondary_count, &mut self.rng);
        let pp = normalize_probs(&wp, g.primary_count);
        let sp = normalize_probs(&ws, g.secondary_count);
        Prediction {
            primary,
            secondary,
            primary_probs: pp,
            secondary_probs: sp,
        }
    }

    fn markov(&mut self, history: &[Draw]) -> Prediction {
        let g = self.game;
        let slice = &history[history.len().saturating_sub(500)..];
        let n = g.primary_max as usize;
        let mut marginal = vec![0.0f64; n + 1];
        for num in 1..=g.primary_max {
            marginal[num as usize] =
                slice.iter().filter(|d| d.contains_primary(num)).count() as f64 / slice.len().max(1) as f64;
        }
        let last_draw = match history.last() {
            Some(d) => d,
            None => return self.random(history),
        };
        let mut scores = marginal.clone();
        for &m in &last_draw.primary {
            let m_count = slice.iter().filter(|d| d.contains_primary(m)).count() as f64;
            if m_count == 0.0 {
                continue;
            }
            for num in 1..=g.primary_max {
                let co = slice
                    .iter()
                    .filter(|d| d.contains_primary(m) && d.contains_primary(num))
                    .count() as f64;
                let cond = co / m_count;
                let lift = cond - marginal[num as usize];
                if lift > 0.0 {
                    scores[num as usize] += lift * 3.0;
                }
            }
        }
        let primary = weighted_sample(&scores, g.primary_count, &mut self.rng);
        let pp = normalize_probs(&scores, g.primary_count);

        let mut ws = vec![0.0f64; g.secondary_max as usize + 1];
        for num in 1..=g.secondary_max {
            ws[num as usize] =
                slice.iter().filter(|d| d.contains_secondary(num)).count() as f64 + 1.0;
        }
        let secondary = weighted_sample(&ws, g.secondary_count, &mut self.rng);
        let sp = normalize_probs(&ws, g.secondary_count);
        Prediction {
            primary,
            secondary,
            primary_probs: pp,
            secondary_probs: sp,
        }
    }

    fn logistic(&mut self, history: &[Draw]) -> Prediction {
        let g = self.game;
        let model = match self.logistic.as_ref() {
            Some(m) => m,
            None => return self.random(history),
        };
        let (pv, sv, pf, sf) = model.probs(history, &g);
        self.last_pf = pf;
        self.last_sf = sf;
        let primary = weighted_sample(&pv, g.primary_count, &mut self.rng);
        let secondary = weighted_sample(&sv, g.secondary_count, &mut self.rng);
        let pp = normalize_probs(&pv, g.primary_count);
        let sp = normalize_probs(&sv, g.secondary_count);
        Prediction {
            primary,
            secondary,
            primary_probs: pp,
            secondary_probs: sp,
        }
    }

    fn balanced(&mut self, _history: &[Draw]) -> Prediction {
        let g = self.game;
        let cfg = self
            .balanced
            .clone()
            .unwrap_or_else(|| balanced_cfg(&[], &g));
        let n = g.primary_max as usize;
        let k = g.primary_count;
        let mut best = self.sample_primary();
        for _ in 0..400 {
            let cand = self.sample_primary();
            let sum: usize = cand.iter().map(|&x| x as usize).sum();
            let odd = cand.iter().filter(|&&x| x % 2 == 1).count();
            let span = cand.last().unwrap() - cand.first().unwrap();
            if sum as f64 >= cfg.sum_lo
                && sum as f64 <= cfg.sum_hi
                && odd >= cfg.odd_lo
                && odd <= cfg.odd_hi
                && span >= cfg.span_lo
            {
                best = cand;
                break;
            }
        }
        let secondary = self.sample_secondary();
        let _ = n;
        let _ = k;
        let (pp, sp) = degenerate_probs(&g, &best, &secondary);
        Prediction {
            primary: best,
            secondary,
            primary_probs: pp,
            secondary_probs: sp,
        }
    }
}

trait WithGame {
    fn with_game(self, g: &GameDef) -> Self;
}

impl WithGame for Prediction {
    fn with_game(mut self, g: &GameDef) -> Self {
        if self.primary_probs.len() != g.primary_max as usize + 1 {
            let (pp, sp) = degenerate_probs(g, &self.primary, &self.secondary);
            self.primary_probs = pp;
            self.secondary_probs = sp;
        }
        self
    }
}

fn balanced_cfg(history: &[Draw], g: &GameDef) -> BalancedCfg {
    let k = g.primary_count;
    let n = g.primary_max as usize;
    let mut sums: Vec<f64> = history
        .iter()
        .map(|d| d.primary.iter().map(|&x| x as f64).sum())
        .collect();
    let (sum_lo, sum_hi) = if sums.len() >= 20 {
        sums.sort_by(|a, b| a.partial_cmp(b).unwrap());
        (
            stats::quantile(&sums, 0.10),
            stats::quantile(&sums, 0.90),
        )
    } else {
        let mean = k as f64 * (n as f64 + 1.0) / 2.0;
        let sd = (k as f64 * (n as f64 + 1.0) * (n as f64 - k as f64) / 12.0).sqrt();
        (mean - 1.28 * sd, mean + 1.28 * sd)
    };
    let odd_lo = ((k as f64) * 0.25).round().max(1.0) as usize;
    BalancedCfg {
        sum_lo,
        sum_hi,
        odd_lo,
        odd_hi: k - odd_lo,
        span_lo: (n as f64 * 0.55) as u8,
    }
}

fn degenerate_probs(g: &GameDef, primary: &[u8], secondary: &[u8]) -> (Vec<f64>, Vec<f64>) {
    let mut pp = vec![0.0f64; g.primary_max as usize + 1];
    for &n in primary {
        if (n as usize) < pp.len() {
            pp[n as usize] = 1.0 / g.primary_count as f64;
        }
    }
    let mut sp = vec![0.0f64; g.secondary_max as usize + 1];
    for &n in secondary {
        if (n as usize) < sp.len() {
            sp[n as usize] = 1.0 / g.secondary_count as f64;
        }
    }
    (pp, sp)
}

fn normalize_probs(weights: &[f64], k: usize) -> Vec<f64> {
    let total: f64 = weights.iter().sum();
    if total <= 0.0 {
        return weights.to_vec();
    }
    weights
        .iter()
        .map(|&w| w / total * k as f64)
        .collect()
}

fn sample_distinct(n: usize, k: usize, rng: &mut impl RngExt) -> Vec<u8> {
    let mut pool: Vec<u8> = (1..=n as u8).collect();
    for i in 0..k.min(n) {
        let j = i + rng.random_range(0..(n - i));
        pool.swap(i, j);
    }
    let mut v = pool[..k.min(n)].to_vec();
    v.sort_unstable();
    v
}

fn weighted_sample(weights: &[f64], k: usize, rng: &mut impl RngExt) -> Vec<u8> {
    let n = weights.len().saturating_sub(1);
    let mut pool: Vec<usize> = (1..=n).collect();
    let mut out = Vec::with_capacity(k);
    for _ in 0..k {
        if pool.is_empty() {
            break;
        }
        let total: f64 = pool.iter().map(|&i| weights[i].max(1e-12)).sum();
        let mut r = rng.random::<f64>() * total;
        let mut chosen = pool.len() - 1;
        for (j, &num) in pool.iter().enumerate() {
            r -= weights[num].max(1e-12);
            if r <= 0.0 {
                chosen = j;
                break;
            }
        }
        out.push(pool.remove(chosen) as u8);
    }
    out.sort_unstable();
    out
}

#[cfg(test)]
pub fn sample_distinct_for_test(n: usize, k: usize, rng: &mut impl RngExt) -> Vec<u8> {
    sample_distinct(n, k, rng)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config;

    fn synthetic_draws(g: &GameDef, count: usize) -> Vec<Draw> {
        let mut rng = ChaCha8Rng::seed_from_u64(7);
        (0..count)
            .map(|i| Draw {
                game: g.id.into(),
                issue: i.to_string(),
                date: format!("2020-01-{:02}", (i % 28) + 1),
                primary: sample_distinct(g.primary_max as usize, g.primary_count, &mut rng),
                secondary: sample_distinct(
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
    fn every_strategy_returns_valid_ticket() {
        let g = config::game("ssq").unwrap();
        let draws = synthetic_draws(g, 200);
        for (i, kind) in StrategyKind::all().iter().enumerate() {
            let mut runner = StrategyRunner::new(*kind, *g, &draws, i as u64);
            let pred = runner.predict(&draws);
            assert_eq!(pred.primary.len(), g.primary_count, "{kind:?}");
            assert_eq!(pred.secondary.len(), g.secondary_count, "{kind:?}");
            assert!(pred.primary.iter().all(|&n| n >= 1 && n <= g.primary_max));
            assert!(pred.secondary.iter().all(|&n| n >= 1 && n <= g.secondary_max));
            let mut sorted = pred.primary.clone();
            sorted.dedup();
            assert_eq!(sorted.len(), g.primary_count, "{kind:?}");
        }
    }

    #[test]
    fn weighted_probs_sum_to_k() {
        let weights = [0.0, 1.0, 2.0, 3.0];
        let p = normalize_probs(&weights, 2);
        let total: f64 = p.iter().sum();
        assert!((total - 2.0).abs() < 1e-9);
    }
}
