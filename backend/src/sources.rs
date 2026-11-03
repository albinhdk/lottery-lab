//! Data acquisition from the official lottery APIs, with a historical
//! fallback for 双色球 seasons before 2013 (500.com).

use anyhow::{Context, Result};
use reqwest::Client;
use serde_json::Value;
use tokio::time::{sleep, Duration};

use crate::config::GameDef;
use crate::models::Draw;

const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
                  (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

const PAGE_SIZE: usize = 100;

/// The periodic freshness check only reads the newest page. 30 issues cover
/// roughly ten weeks of either game.
const RECENT_PAGE_SIZE: usize = 30;

fn client() -> Result<Client> {
    // Use Mozilla's bundled roots instead of the platform verifier. The
    // platform verifier needs JNI/Android Context initialization, while the
    // same binary also runs embedded inside the Android app process.
    let mut roots = rustls::RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let tls = rustls::ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth();
    Client::builder()
        .user_agent(UA)
        .timeout(Duration::from_secs(25))
        .tls_backend_preconfigured(tls)
        .build()
        .context("build http client")
}

fn parse_nums(s: &str) -> Vec<u8> {
    s.split(|c: char| c == ',' || c.is_whitespace())
        .filter_map(|x| x.trim().parse::<u8>().ok())
        .collect()
}

fn short_date(s: &str) -> String {
    let s = s.trim();
    if s.len() >= 10 {
        s[..10].to_string()
    } else {
        s.to_string()
    }
}

fn parse_money(s: &str) -> Option<i64> {
    let clean = s.replace(',', "");
    clean.parse::<f64>().ok().map(|v| v.round() as i64)
}

fn snippet(text: &str, max_chars: usize) -> String {
    text.chars().take(max_chars).collect()
}

/// GET with up to three attempts. The official endpoints occasionally time
/// out or answer 5xx; without a retry a single flaky page used to abort the
/// whole sync.
async fn fetch_text(
    client: &Client,
    url: &str,
    headers: &[(&str, &str)],
    what: &str,
) -> Result<String> {
    let mut last_error = String::from("未知错误");
    for attempt in 1..=3u32 {
        let mut request = client.get(url);
        for (name, value) in headers {
            request = request.header(*name, *value);
        }
        match request.send().await {
            Ok(response) => {
                let status = response.status();
                let text = response.text().await.unwrap_or_default();
                if status.is_success() {
                    return Ok(text);
                }
                last_error = format!("{status}: {}", snippet(&text, 200));
            }
            Err(err) => last_error = format!("{err:#}"),
        }
        if attempt < 3 {
            sleep(Duration::from_millis(700 * u64::from(attempt))).await;
        }
    }
    anyhow::bail!("{what} 请求失败（已重试 3 次）: {last_error}")
}

/// One page of the official 双色球 API. Returns the parsed draws and the
/// total number of pages.
async fn fetch_ssq_page(
    client: &Client,
    page: usize,
    page_size: usize,
) -> Result<(Vec<Draw>, usize)> {
    let url = format!(
        "https://www.cwl.gov.cn/cwl_admin/front/cwlkj/search/kjxx/findDrawNotice\
         ?name=ssq&issueCount=&issueStart=&issueEnd=&dayStart=&dayEnd=\
         &pageNo={page}&pageSize={page_size}&week=&systemType=PC"
    );
    let text = fetch_text(
        client,
        &url,
        &[("Referer", "https://www.cwl.gov.cn/")],
        "cwl ssq",
    )
    .await?;
    let v: Value = serde_json::from_str(&text).context("parse cwl ssq json")?;
    if v["state"].as_i64().unwrap_or(-1) != 0 {
        anyhow::bail!("cwl ssq error: {}", v["message"]);
    }
    let total = v["total"].as_u64().unwrap_or(0) as usize;
    let pages = total.div_ceil(page_size).max(1);
    let mut draws = Vec::new();
    if let Some(arr) = v["result"].as_array() {
        for item in arr {
            let issue = item["code"].as_str().unwrap_or("").to_string();
            let red = parse_nums(item["red"].as_str().unwrap_or(""));
            let blue = parse_nums(item["blue"].as_str().unwrap_or(""));
            if issue.is_empty() || red.len() != 6 || blue.len() != 1 {
                continue;
            }
            draws.push(Draw {
                game: "ssq".into(),
                issue,
                date: short_date(item["date"].as_str().unwrap_or("")),
                primary: red,
                secondary: blue,
                sales: item["sales"].as_str().and_then(|s| s.parse().ok()),
                pool: item["poolmoney"].as_str().and_then(|s| s.parse().ok()),
            });
        }
    }
    Ok((draws, pages))
}

/// Fetch every page of the official 双色球 API (data starts in 2013).
pub async fn fetch_ssq_official() -> Result<Vec<Draw>> {
    let client = client()?;
    let mut all = Vec::new();
    let mut page = 1usize;
    loop {
        let (mut draws, pages) = fetch_ssq_page(&client, page, PAGE_SIZE).await?;
        if draws.is_empty() {
            break;
        }
        all.append(&mut draws);
        if page >= pages {
            break;
        }
        page += 1;
        sleep(Duration::from_millis(120)).await;
    }
    all.sort_by(|a, b| a.date.cmp(&b.date));
    all.dedup_by(|a, b| a.issue == b.issue);
    Ok(all)
}

/// One page of the official 超级大乐透 API. Returns the parsed draws and the
/// total number of pages.
async fn fetch_dlt_page(
    client: &Client,
    page: usize,
    page_size: usize,
) -> Result<(Vec<Draw>, usize)> {
    let url = format!(
        "https://webapi.sporttery.cn/gateway/lottery/getHistoryPageListV1.qry\
         ?gameNo=85&provinceId=0&pageSize={page_size}&isVerify=1&pageNo={page}"
    );
    let text = fetch_text(
        client,
        &url,
        &[
            ("Referer", "https://www.sporttery.cn/"),
            ("Origin", "https://www.sporttery.cn"),
        ],
        "sporttery dlt",
    )
    .await?;
    let v: Value = serde_json::from_str(&text).context("parse sporttery json")?;
    if !v["success"].as_bool().unwrap_or(false) {
        anyhow::bail!("sporttery dlt error: {}", v["errorMessage"]);
    }
    let pages = v["value"]["pages"].as_u64().unwrap_or(1) as usize;
    let mut draws = Vec::new();
    if let Some(arr) = v["value"]["list"].as_array() {
        for item in arr {
            let issue = item["lotteryDrawNum"].as_str().unwrap_or("").to_string();
            let nums = parse_nums(item["lotteryDrawResult"].as_str().unwrap_or(""));
            if issue.is_empty() || nums.len() != 7 {
                continue;
            }
            draws.push(Draw {
                game: "dlt".into(),
                issue,
                date: short_date(item["lotteryDrawTime"].as_str().unwrap_or("")),
                primary: nums[..5].to_vec(),
                secondary: nums[5..].to_vec(),
                sales: item["totalSaleAmount"].as_str().and_then(parse_money),
                pool: item["poolBalanceAfterdraw"].as_str().and_then(parse_money),
            });
        }
    }
    Ok((draws, pages))
}

/// Fetch every page of the official 超级大乐透 API (data starts in 2007).
pub async fn fetch_dlt_official() -> Result<Vec<Draw>> {
    let client = client()?;
    let mut all = Vec::new();
    let mut page = 1usize;
    loop {
        let (mut draws, pages) = fetch_dlt_page(&client, page, PAGE_SIZE).await?;
        if draws.is_empty() {
            break;
        }
        all.append(&mut draws);
        if page >= pages {
            break;
        }
        page += 1;
        sleep(Duration::from_millis(120)).await;
    }
    all.sort_by(|a, b| a.date.cmp(&b.date));
    all.dedup_by(|a, b| a.issue == b.issue);
    Ok(all)
}

/// Fetch only the newest page of a game's official feed. This is what the
/// periodic background sync uses, so a freshness check costs one request per
/// game instead of walking the whole history.
pub async fn fetch_recent(game_id: &str) -> Result<Vec<Draw>> {
    let client = client()?;
    match game_id {
        "ssq" => Ok(fetch_ssq_page(&client, 1, RECENT_PAGE_SIZE).await?.0),
        "dlt" => Ok(fetch_dlt_page(&client, 1, RECENT_PAGE_SIZE).await?.0),
        other => anyhow::bail!("unknown game {other}"),
    }
}

/// 500.com history table for 双色球 seasons 2003–2012 (the official API only
/// keeps data from 2013 onwards).
pub async fn fetch_ssq_history_500() -> Result<Vec<Draw>> {
    let client = client()?;
    let url = "https://datachart.500.com/ssq/history/newinc/history.php\
               ?start=03001&end=2012154";
    let resp = client
        .get(url)
        .header("Referer", "https://datachart.500.com/ssq/history/history.shtml")
        .send()
        .await
        .context("request 500 ssq history")?;
    let text = resp.text().await.context("read 500 body")?;
    Ok(parse_500_ssq(&text))
}

fn clean_cell(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_tag = false;
    for ch in s.chars() {
        match ch {
            '<' => in_tag = true,
            '>' => in_tag = false,
            _ if !in_tag => out.push(ch),
            _ => {}
        }
    }
    out.replace("&nbsp;", " ")
        .replace("&amp;", "&")
        .trim()
        .to_string()
}

fn extract_cells(row: &str) -> Vec<String> {
    let mut cells = Vec::new();
    let mut rest = row;
    while let Some(start) = rest.find("<td") {
        let after = &rest[start..];
        let Some(open_end) = after.find('>') else { break };
        let content = &after[open_end + 1..];
        let Some(close) = content.find("</td>") else { break };
        cells.push(clean_cell(&content[..close]));
        rest = &content[close + 5..];
    }
    cells
}

fn strip_comments(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(start) = rest.find("<!--") {
        out.push_str(&rest[..start]);
        match rest[start..].find("-->") {
            Some(end) => rest = &rest[start + end + 3..],
            None => {
                rest = "";
                break;
            }
        }
    }
    out.push_str(rest);
    out
}

pub fn parse_500_ssq(html: &str) -> Vec<Draw> {
    let html = strip_comments(html);
    let mut out = Vec::new();
    for chunk in html.split("<tr class=\"t_tr1\">").skip(1) {
        let row = chunk.split("</tr>").next().unwrap_or("");
        let cells = extract_cells(row);
        if cells.len() < 9 {
            continue;
        }
        let issue = cells[0].trim().to_string();
        if issue.len() < 5 || !issue.chars().all(|c| c.is_ascii_digit()) {
            continue;
        }
        let primary: Vec<u8> = cells[1..7]
            .iter()
            .filter_map(|c| c.trim().parse::<u8>().ok())
            .collect();
        let secondary: Vec<u8> = cells[7..8]
            .iter()
            .filter_map(|c| c.trim().parse::<u8>().ok())
            .collect();
        if primary.len() != 6 || secondary.len() != 1 {
            continue;
        }
        let date = cells
            .iter()
            .rev()
            .map(|c| c.trim())
            .find(|c| {
                c.len() == 10
                    && c.as_bytes()[4] == b'-'
                    && c.chars().all(|ch| ch.is_ascii_digit() || ch == '-')
            })
            .unwrap_or("")
            .to_string();
        if date.is_empty() {
            continue;
        }
        out.push(Draw {
            game: "ssq".into(),
            issue,
            date,
            primary,
            secondary,
            sales: None,
            pool: None,
        });
    }
    out.sort_by(|a, b| a.date.cmp(&b.date));
    out
}

pub async fn sync(game_id: &str, full: bool, _g: &GameDef) -> Result<Vec<Draw>> {
    match game_id {
        "ssq" => {
            let mut all = fetch_ssq_official().await?;
            if full {
                if let Ok(old) = fetch_ssq_history_500().await {
                    let newest_official = all
                        .iter()
                        .map(|d| d.date.clone())
                        .min()
                        .unwrap_or_default();
                    for d in old {
                        if newest_official.is_empty() || d.date.as_str() < newest_official.as_str() {
                            all.push(d);
                        }
                    }
                }
            }
            all.sort_by(|a, b| a.date.cmp(&b.date));
            all.dedup_by(|a, b| a.issue == b.issue);
            Ok(all)
        }
        "dlt" => fetch_dlt_official().await,
        other => anyhow::bail!("unknown game {other}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_500_row() {
        let html = r#"
        <tr class="t_tr1"><!--<td>2</td>--><td class="t_tr1">03020</td><td class="t_cfont2">07</td><td class="t_cfont2">10</td><td class="t_cfont2">25</td><td class="t_cfont2">26</td><td class="t_cfont2">27</td><td class="t_cfont2">32</td><td class="t_cfont4">04</td><td class="t_cfont4">0&nbsp;</td><td>8,846,550</td><td>5</td><td>5,000,000</td><td>3</td><td>327,334</td><td>14,670,860</td><td>2003-05-01</td></tr>
        "#;
        let draws = parse_500_ssq(html);
        assert_eq!(draws.len(), 1);
        assert_eq!(draws[0].issue, "03020");
        assert_eq!(draws[0].primary, vec![7, 10, 25, 26, 27, 32]);
        assert_eq!(draws[0].secondary, vec![4]);
        assert_eq!(draws[0].date, "2003-05-01");
    }
}
