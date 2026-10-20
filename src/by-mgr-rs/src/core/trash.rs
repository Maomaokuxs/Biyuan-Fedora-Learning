use anyhow::{anyhow, Result};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::config::AppConfig;

/// 回收站根目录：~/.config/by-mgr/trash
/// 布局（与 bash lib/utils.sh 的 trash_move 互通）：
///   <批次时间戳>/op        来源操作（一行文本）
///   <批次时间戳>/items.txt 每行一个被删条目的原绝对路径
///   <批次时间戳>/files/... 按原路径（相对 HOME）镜像存放
pub fn trash_root(cfg: &AppConfig) -> PathBuf {
    cfg.user_config_dir.join("trash")
}

#[derive(Debug, Clone)]
pub struct Batch {
    pub dir: PathBuf,
    pub name: String,
    pub op: String,
    pub items: Vec<String>,
}

/// 列出全部批次（新→旧）
pub fn list_batches(cfg: &AppConfig) -> Vec<Batch> {
    let root = trash_root(cfg);
    let mut batches = Vec::new();
    if let Ok(rd) = std::fs::read_dir(&root) {
        for e in rd.flatten() {
            let p = e.path();
            if !p.is_dir() {
                continue;
            }
            let name = e.file_name().to_string_lossy().to_string();
            let op = std::fs::read_to_string(p.join("op"))
                .map(|s| s.trim().to_string())
                .unwrap_or_else(|_| "?".to_string());
            let items = std::fs::read_to_string(p.join("items.txt"))
                .map(|s| {
                    s.lines()
                        .map(|l| l.trim().to_string())
                        .filter(|l| !l.is_empty())
                        .collect()
                })
                .unwrap_or_default();
            batches.push(Batch { dir: p, name, op, items });
        }
    }
    batches.sort_by(|a, b| b.name.cmp(&a.name));
    batches
}

/// 解析批次目标：编号（1 起，新→旧）/ 批次名 / last / -1
pub fn resolve_batch(cfg: &AppConfig, target: &str) -> Result<Batch> {
    let batches = list_batches(cfg);
    if batches.is_empty() {
        anyhow::bail!("回收站是空的");
    }
    if target == "last" || target == "-1" {
        return Ok(batches[0].clone());
    }
    if let Ok(n) = target.parse::<usize>() {
        if n >= 1 && n <= batches.len() {
            return Ok(batches[n - 1].clone());
        }
        anyhow::bail!("批次编号 {} 不存在（共 {} 个批次）", n, batches.len());
    }
    batches
        .iter()
        .find(|b| b.name == target)
        .cloned()
        .ok_or_else(|| anyhow!("找不到回收站批次: {}", target))
}

/// 原路径在批次 files/ 下的镜像相对路径（相对 HOME；不在 HOME 下则去掉根前缀）
fn rel_in_trash(home: &Path, path: &Path) -> PathBuf {
    if let Ok(rel) = path.strip_prefix(home) {
        return rel.to_path_buf();
    }
    path.components()
        .filter(|c| !matches!(c, std::path::Component::RootDir))
        .collect()
}

static BATCH: Mutex<Option<PathBuf>> = Mutex::new(None);

fn ensure_batch(cfg: &AppConfig, op: &str) -> Result<PathBuf> {
    let mut guard = BATCH.lock().unwrap();
    if let Some(b) = guard.as_ref() {
        return Ok(b.clone());
    }
    let root = trash_root(cfg);
    let ts = chrono::Local::now().format("%Y%m%d_%H%M%S").to_string();
    let mut dir = root.join(&ts);
    let mut i = 1;
    while dir.exists() {
        dir = root.join(format!("{}_{}", ts, i));
        i += 1;
    }
    std::fs::create_dir_all(dir.join("files"))?;
    std::fs::write(dir.join("op"), format!("{}\n", op))?;
    std::fs::write(dir.join("items.txt"), "")?;
    *guard = Some(dir.clone());
    Ok(dir)
}

/// Rust 侧删除入口：把路径移入回收站（同进程共用一个批次）。
/// 路径不存在时静默跳过；rename 失败（如跨设备）时回退为复制后删除。
pub fn trash_move(cfg: &AppConfig, path: &Path, op: &str) -> Result<()> {
    if !path.exists() && !path.is_symlink() {
        return Ok(());
    }
    let batch = ensure_batch(cfg, op)?;
    let home = crate::config::home_dir()?;
    let rel = rel_in_trash(&home, path);
    let dest = batch.join("files").join(&rel);
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent)?;
    }
    if std::fs::rename(path, &dest).is_err() {
        if path.is_dir() && !path.is_symlink() {
            crate::core::utils::copy_recursive(path, &dest)?;
            std::fs::remove_dir_all(path)?;
        } else {
            std::fs::copy(path, &dest)?;
            std::fs::remove_file(path)?;
        }
    }
    let mut f = std::fs::OpenOptions::new()
        .append(true)
        .open(batch.join("items.txt"))?;
    writeln!(f, "{}", path.display())?;
    Ok(())
}

/// 把批次内全部条目放回原位；原位已被占用则跳过并保留在批次中。
/// 返回 (已恢复数, 冲突的原路径列表)
pub fn restore_batch(cfg: &AppConfig, target: &str) -> Result<(usize, Vec<String>)> {
    let batch = resolve_batch(cfg, target)?;
    let home = crate::config::home_dir()?;
    let mut restored = 0usize;
    let mut conflicts: Vec<String> = Vec::new();
    let mut remaining: Vec<String> = Vec::new();
    for item in &batch.items {
        let orig = PathBuf::from(item);
        let rel = rel_in_trash(&home, &orig);
        let src = batch.dir.join("files").join(&rel);
        if !src.exists() && !src.is_symlink() {
            continue; // 已不在回收站内（已恢复或丢失），不再跟踪
        }
        if orig.exists() || orig.is_symlink() {
            conflicts.push(item.clone());
            remaining.push(item.clone());
            continue;
        }
        if let Some(parent) = orig.parent() {
            std::fs::create_dir_all(parent)?;
        }
        if std::fs::rename(&src, &orig).is_err() {
            if src.is_dir() && !src.is_symlink() {
                crate::core::utils::copy_recursive(&src, &orig)?;
                std::fs::remove_dir_all(&src)?;
            } else {
                std::fs::copy(&src, &orig)?;
                std::fs::remove_file(&src)?;
            }
        }
        restored += 1;
    }
    if remaining.is_empty() {
        let _ = std::fs::remove_dir_all(&batch.dir);
    } else {
        std::fs::write(batch.dir.join("items.txt"), remaining.join("\n") + "\n")?;
    }
    Ok((restored, conflicts))
}

/// 永久清空：target 为 None 清全部批次。返回清掉的批次数。
pub fn empty_trash(cfg: &AppConfig, target: Option<&str>) -> Result<usize> {
    match target {
        Some(t) => {
            let b = resolve_batch(cfg, t)?;
            std::fs::remove_dir_all(&b.dir)?;
            Ok(1)
        }
        None => {
            let batches = list_batches(cfg);
            let n = batches.len();
            for b in &batches {
                std::fs::remove_dir_all(&b.dir)?;
            }
            Ok(n)
        }
    }
}

fn dir_size(p: &Path) -> u64 {
    walkdir::WalkDir::new(p)
        .into_iter()
        .flatten()
        .filter_map(|e| e.metadata().ok())
        .filter(|m| m.is_file())
        .map(|m| m.len())
        .sum()
}

fn fmt_size(n: u64) -> String {
    if n >= 1 << 20 {
        format!("{:.1}M", n as f64 / (1 << 20) as f64)
    } else if n >= 1 << 10 {
        format!("{:.1}K", n as f64 / (1 << 10) as f64)
    } else {
        format!("{}B", n)
    }
}

pub fn trash_list_cli(cfg: &AppConfig) -> Result<()> {
    let batches = list_batches(cfg);
    if batches.is_empty() {
        println!("（回收站是空的）");
        return Ok(());
    }
    let pad = crate::core::utils::pad_display;
    println!(
        " {} {} {} {} {}",
        pad("编号", 4),
        pad("批次", 17),
        pad("来源", 8),
        pad("条目", 4),
        "大小"
    );
    println!(
        " {} {} {} {} {}",
        "-".repeat(4),
        "-".repeat(17),
        "-".repeat(8),
        "-".repeat(4),
        "-".repeat(4)
    );
    for (i, b) in batches.iter().enumerate() {
        println!(
            " {} {} {} {} {}",
            pad(&(i + 1).to_string(), 4),
            pad(&b.name, 17),
            pad(&b.op, 8),
            pad(&b.items.len().to_string(), 4),
            fmt_size(dir_size(&b.dir.join("files")))
        );
    }
    Ok(())
}

pub fn trash_restore_cli(cfg: &AppConfig, target: &str) -> Result<()> {
    let batch = resolve_batch(cfg, target)?;
    let (restored, conflicts) = restore_batch(cfg, target)?;
    println!("✅ 已从批次 {} 恢复 {} 个条目", batch.name, restored);
    if !conflicts.is_empty() {
        println!("⚠️ 以下路径原位已被占用，已跳过（仍留在回收站）:");
        for c in &conflicts {
            println!("  {}", c);
        }
    }
    Ok(())
}

pub fn trash_empty_cli(cfg: &AppConfig, target: Option<&str>) -> Result<()> {
    let n = empty_trash(cfg, target)?;
    match target {
        Some(t) => println!("✅ 已永久删除回收站批次 {}", t),
        None => println!("✅ 已永久清空回收站（{} 个批次）", n),
    }
    Ok(())
}
