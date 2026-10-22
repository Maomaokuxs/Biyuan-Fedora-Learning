use anyhow::{anyhow, Result};
use std::path::PathBuf;

/// 日志目录：与所有写入侧一致（BY_MGR_LOG_DIR 优先，否则 XDG_STATE_HOME/by-mgr）
pub fn log_dir() -> PathBuf {
    if let Ok(d) = std::env::var("BY_MGR_LOG_DIR") {
        if !d.is_empty() {
            return PathBuf::from(d);
        }
    }
    dirs::home_dir()
        .map(|h| h.join(".local/state/by-mgr"))
        .unwrap_or_else(|| PathBuf::from("/tmp/by-mgr"))
}

fn human_size(n: u64) -> String {
    if n < 1024 {
        format!("{} B", n)
    } else if n < 1024 * 1024 {
        format!("{:.1} KB", n as f64 / 1024.0)
    } else {
        format!("{:.1} MB", n as f64 / 1024.0 / 1024.0)
    }
}

fn collect(dir: &PathBuf) -> Vec<(String, std::time::SystemTime, u64)> {
    let mut v = Vec::new();
    if let Ok(rd) = std::fs::read_dir(dir) {
        for e in rd.flatten() {
            let p = e.path();
            if p.extension().map(|x| x == "log").unwrap_or(false) {
                if let Ok(m) = e.metadata() {
                    let name = p.file_stem().unwrap_or_default().to_string_lossy().into_owned();
                    v.push((name, m.modified().unwrap_or(std::time::UNIX_EPOCH), m.len()));
                }
            }
        }
    }
    v.sort_by(|a, b| b.1.cmp(&a.1));
    v
}

pub fn log_cli(name: Option<&str>) -> Result<()> {
    let dir = log_dir();
    match name {
        None => {
            let logs = collect(&dir);
            if logs.is_empty() {
                println!("暂无日志（目录 {}）", dir.display());
                return Ok(());
            }
            println!("日志目录: {}", dir.display());
            for (n, t, sz) in &logs {
                let when = chrono::DateTime::<chrono::Local>::from(*t).format("%Y-%m-%d %H:%M");
                println!("  {:<12} {}  {}", n, when, human_size(*sz));
            }
            println!("查看: by-mgr log <名称>");
            Ok(())
        }
        Some(n) => {
            let stem = n.strip_suffix(".log").unwrap_or(n);
            let path = dir.join(format!("{}.log", stem));
            if !path.is_file() {
                let avail: Vec<String> = collect(&dir).into_iter().map(|x| x.0).collect();
                return Err(anyhow!("没有名为 {} 的日志（可用: {}）", stem, avail.join("、")));
            }
            let content = std::fs::read_to_string(&path)
                .map_err(|e| anyhow!("读取 {} 失败: {}", path.display(), e))?;
            print!("{}", content);
            Ok(())
        }
    }
}
