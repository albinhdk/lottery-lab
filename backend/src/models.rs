use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Draw {
    pub game: String,
    pub issue: String,
    pub date: String,
    pub primary: Vec<u8>,
    pub secondary: Vec<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sales: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pool: Option<i64>,
}

impl Draw {
    pub fn contains_primary(&self, n: u8) -> bool {
        self.primary.contains(&n)
    }

    pub fn contains_secondary(&self, n: u8) -> bool {
        self.secondary.contains(&n)
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct Page<T> {
    pub items: Vec<T>,
    pub page: usize,
    pub page_size: usize,
    pub total: usize,
    pub pages: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct Prediction {
    pub primary: Vec<u8>,
    pub secondary: Vec<u8>,
    /// Calibrated (or degenerate) per-number probabilities, index 1..=max.
    pub primary_probs: Vec<f64>,
    pub secondary_probs: Vec<f64>,
}
