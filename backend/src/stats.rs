//! Small, dependency-free statistical toolkit used by the analysis and
//! backtesting engines. Everything here is deterministic and unit-tested.

pub fn mean(xs: &[f64]) -> f64 {
    if xs.is_empty() {
        return 0.0;
    }
    xs.iter().sum::<f64>() / xs.len() as f64
}

pub fn variance(xs: &[f64], sample: bool) -> f64 {
    if xs.len() < 2 {
        return 0.0;
    }
    let m = mean(xs);
    let ss: f64 = xs.iter().map(|x| (x - m) * (x - m)).sum();
    ss / (xs.len() as f64 - if sample { 1.0 } else { 0.0 })
}

pub fn std_dev(xs: &[f64], sample: bool) -> f64 {
    variance(xs, sample).sqrt()
}

pub fn pearson(xs: &[f64], ys: &[f64]) -> f64 {
    let n = xs.len().min(ys.len());
    if n < 3 {
        return 0.0;
    }
    let mx = mean(&xs[..n]);
    let my = mean(&ys[..n]);
    let mut num = 0.0;
    let mut dx = 0.0;
    let mut dy = 0.0;
    for i in 0..n {
        let a = xs[i] - mx;
        let b = ys[i] - my;
        num += a * b;
        dx += a * a;
        dy += b * b;
    }
    if dx == 0.0 || dy == 0.0 {
        0.0
    } else {
        num / (dx.sqrt() * dy.sqrt())
    }
}

/// Abramowitz & Stegun 7.1.26, max error ~1.5e-7.
pub fn erf(x: f64) -> f64 {
    let sign = if x < 0.0 { -1.0 } else { 1.0 };
    let x = x.abs();
    let t = 1.0 / (1.0 + 0.327_591_1 * x);
    let y = 1.0
        - (((((1.061_405_429 * t - 1.453_152_027) * t) + 1.421_413_741) * t - 0.284_496_736)
            * t
            + 0.254_829_592)
            * t
            * (-x * x).exp();
    sign * y
}

pub fn normal_cdf(z: f64) -> f64 {
    0.5 * (1.0 + erf(z / std::f64::consts::SQRT_2))
}

pub fn normal_two_sided_p(z: f64) -> f64 {
    (2.0 * (1.0 - normal_cdf(z.abs()))).clamp(0.0, 1.0)
}

pub fn ln_gamma(x: f64) -> f64 {
    const G: f64 = 7.0;
    const C: [f64; 9] = [
        0.999_999_999_999_809_93,
        676.520_368_121_885_1,
        -1_259.139_216_722_402_8,
        771.323_428_777_653_1,
        -176.615_029_162_140_6,
        12.507_343_278_686_905,
        -0.138_571_095_265_720_12,
        9.984_369_578_019_572e-6,
        1.505_632_735_149_311_6e-7,
    ];
    if x < 0.5 {
        std::f64::consts::PI.ln() - (std::f64::consts::PI * x).sin().ln() - ln_gamma(1.0 - x)
    } else {
        let x = x - 1.0;
        let mut a = C[0];
        let t = x + G + 0.5;
        for (i, &c) in C.iter().enumerate().skip(1) {
            a += c / (x + i as f64);
        }
        0.5 * (2.0 * std::f64::consts::PI).ln() + (x + 0.5) * t.ln() - t + a.ln()
    }
}

fn gamma_series(a: f64, x: f64) -> f64 {
    let mut ap = a;
    let mut sum = 1.0 / a;
    let mut del = sum;
    for _ in 0..1000 {
        ap += 1.0;
        del *= x / ap;
        sum += del;
        if del.abs() < sum.abs() * 1e-14 {
            break;
        }
    }
    sum * (-x + a * x.ln() - ln_gamma(a)).exp()
}

fn gamma_cont_frac(a: f64, x: f64) -> f64 {
    let fpmin = 1e-300;
    let mut b = x + 1.0 - a;
    let mut c = 1.0 / fpmin;
    let mut d = 1.0 / b;
    let mut h = d;
    for i in 1..1000 {
        let an = -(i as f64) * (i as f64 - a);
        b += 2.0;
        d = an * d + b;
        if d.abs() < fpmin {
            d = fpmin;
        }
        c = b + an / c;
        if c.abs() < fpmin {
            c = fpmin;
        }
        d = 1.0 / d;
        let del = d * c;
        h *= del;
        if (del - 1.0).abs() < 1e-14 {
            break;
        }
    }
    (-x + a * x.ln() - ln_gamma(a)).exp() * h
}

/// Regularized upper incomplete gamma Q(a, x).
pub fn gamma_q(a: f64, x: f64) -> f64 {
    if !(a > 0.0) || x < 0.0 {
        return f64::NAN;
    }
    if x == 0.0 {
        return 1.0;
    }
    if x < a + 1.0 {
        (1.0 - gamma_series(a, x)).clamp(0.0, 1.0)
    } else {
        gamma_cont_frac(a, x).clamp(0.0, 1.0)
    }
}

pub fn chi_square_sf(x: f64, df: usize) -> f64 {
    if df == 0 {
        return 1.0;
    }
    gamma_q(df as f64 / 2.0, x / 2.0)
}

pub fn entropy(counts: &[f64]) -> f64 {
    let total: f64 = counts.iter().sum();
    if total <= 0.0 {
        return 0.0;
    }
    counts
        .iter()
        .filter(|&&c| c > 0.0)
        .map(|&c| {
            let p = c / total;
            -p * p.ln()
        })
        .sum()
}

/// Runs test for a binary sequence. Returns (runs, expected_runs, z).
pub fn runs_test(bits: &[bool]) -> (f64, f64, f64) {
    let n1 = bits.iter().filter(|&&b| b).count() as f64;
    let n2 = bits.iter().filter(|&&b| !b).count() as f64;
    let n = n1 + n2;
    if n1 == 0.0 || n2 == 0.0 || n < 2.0 {
        return (1.0, 1.0, 0.0);
    }
    let mut runs = 1.0;
    for i in 1..bits.len() {
        if bits[i] != bits[i - 1] {
            runs += 1.0;
        }
    }
    let expected = 1.0 + 2.0 * n1 * n2 / n;
    let var = 2.0 * n1 * n2 * (2.0 * n1 * n2 - n) / (n * n * (n - 1.0));
    let z = if var > 0.0 {
        (runs - expected) / var.sqrt()
    } else {
        0.0
    };
    (runs, expected, z)
}

/// Fisher z-transform test for a correlation coefficient.
pub fn correlation_p(r: f64, n: usize) -> f64 {
    if n < 4 {
        return 1.0;
    }
    let r = r.clamp(-0.999_999, 0.999_999);
    let z = 0.5 * ((1.0 + r) / (1.0 - r)).ln() * ((n - 3) as f64).sqrt();
    normal_two_sided_p(z)
}

pub fn combinations(n: usize, k: usize) -> f64 {
    if k > n {
        return 0.0;
    }
    let k = k.min(n - k);
    let mut out = 1.0;
    for i in 0..k {
        out = out * (n - i) as f64 / (i + 1) as f64;
    }
    out
}

/// P(X >= k) for X ~ Binomial(n, p).
pub fn binomial_tail(n: usize, k: usize, p: f64) -> f64 {
    if k > n {
        return 0.0;
    }
    let mut sum = 0.0;
    for i in k..=n {
        sum += combinations(n, i) * p.powi(i as i32) * (1.0 - p).powi((n - i) as i32);
    }
    sum.clamp(0.0, 1.0)
}

pub fn quantile(sorted: &[f64], q: f64) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    let pos = (sorted.len() - 1) as f64 * q.clamp(0.0, 1.0);
    let lo = pos.floor() as usize;
    let hi = pos.ceil() as usize;
    if lo == hi {
        sorted[lo]
    } else {
        sorted[lo] * (hi as f64 - pos) + sorted[hi] * (pos - lo as f64)
    }
}

/// Chi-square goodness of fit with automatic merging of expected counts < 5.
/// `observed` and `expected` must have the same length.
pub fn chi_square_gof(observed: &[f64], expected: &[f64]) -> (f64, usize) {
    let mut obs_bins = Vec::new();
    let mut exp_bins = Vec::new();
    let mut tail_obs = 0.0;
    let mut tail_exp = 0.0;
    let mut tail_started = false;
    for i in 0..observed.len() {
        if expected[i] < 5.0 {
            tail_started = true;
            tail_obs += observed[i];
            tail_exp += expected[i];
        } else {
            if tail_started {
                // merge the low-expectation run into the next valid bin
                obs_bins.push(observed[i] + tail_obs);
                exp_bins.push(expected[i] + tail_exp);
                tail_obs = 0.0;
                tail_exp = 0.0;
                tail_started = false;
            } else {
                obs_bins.push(observed[i]);
                exp_bins.push(expected[i]);
            }
        }
    }
    if tail_started {
        if let Some(last) = exp_bins.last_mut() {
            *last += tail_exp;
            if let Some(olast) = obs_bins.last_mut() {
                *olast += tail_obs;
            }
        } else {
            exp_bins.push(tail_exp);
            obs_bins.push(tail_obs);
        }
    }
    let mut chi = 0.0;
    for i in 0..obs_bins.len() {
        if exp_bins[i] > 0.0 {
            let d = obs_bins[i] - exp_bins[i];
            chi += d * d / exp_bins[i];
        }
    }
    (chi, obs_bins.len().saturating_sub(1))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normal_quantiles() {
        assert!((normal_cdf(0.0) - 0.5).abs() < 1e-6);
        assert!((normal_cdf(1.96) - 0.975).abs() < 1e-3);
        assert!((normal_two_sided_p(1.96) - 0.05).abs() < 2e-3);
    }

    #[test]
    fn chi_square_known_value() {
        // df=1, x=3.841 -> p ~= 0.05
        let p = chi_square_sf(3.841, 1);
        assert!((p - 0.05).abs() < 2e-3, "p={p}");
        // df=10, x=18.307 -> p ~= 0.05
        let p = chi_square_sf(18.307, 10);
        assert!((p - 0.05).abs() < 2e-3, "p={p}");
    }

    #[test]
    fn runs_of_alternating_sequence() {
        let bits = [true, false, true, false, true, false, true, false];
        let (runs, expected, z) = runs_test(&bits);
        assert_eq!(runs, 8.0);
        assert!(expected > 0.0);
        assert!(z > 0.0);
    }

    #[test]
    fn gof_merges_small_expected_bins() {
        let obs = [1.0, 2.0, 10.0, 12.0];
        let exp = [2.0, 3.0, 10.0, 12.0];
        let (chi, df) = chi_square_gof(&obs, &exp);
        assert!(chi > 0.0);
        assert_eq!(df, 1);
    }
}
