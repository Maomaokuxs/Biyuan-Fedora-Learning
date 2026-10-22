use anyhow::{anyhow, Result};
use std::path::{Path, PathBuf};
use crate::config::AppConfig;
use crate::core::run_lib;

pub const META_FILE: &str = ".bymgr-meta.json";

/// 读取快照备注（无 meta 或解析失败返回 None）
pub fn read_note(dir: &Path) -> Option<String> {
    let content = std::fs::read_to_string(dir.join(META_FILE)).ok()?;
    let v: serde_json::Value = serde_json::from_str(&content).ok()?;
    v.get("note").and_then(|n| n.as_str()).map(|s| s.to_string())
}

/// 写入快照备注到该快照目录的 meta 文件（方案 A：自包含）
pub fn write_note(dir: &Path, note: &str) -> Result<()> {
    let created = dir.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    let v = serde_json::json!({"note": note, "created": created});
    std::fs::write(dir.join(META_FILE), serde_json::to_string_pretty(&v)?)?;
    Ok(())
}

/// 全部快照目录（新→旧，与 list / restore 编号一致）
/// 快照目录名格式：YYYYMMDD_HHMMSS（与 bash list_snapshots 的匹配规则对齐，
/// 避免杂目录导致两边编号错位）
fn is_snapshot_name(name: &str) -> bool {
    let b = name.as_bytes();
    name.len() == 15
        && b[8] == b'_'
        && b[..8].iter().all(|c| c.is_ascii_digit())
        && b[9..].iter().all(|c| c.is_ascii_digit())
}

pub fn snapshot_dirs(cfg: &AppConfig) -> Vec<PathBuf> {
    let mut list: Vec<PathBuf> = std::fs::read_dir(&cfg.backup_root)
        .map(|it| {
            it.flatten()
                .filter(|e| {
                    e.path().is_dir()
                        && is_snapshot_name(&e.file_name().to_string_lossy())
                })
                .map(|e| e.path())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    list.sort();
    list.reverse();
    list
}

/// 按标识解析快照目录：last/-1 / 编号(1 起，新→旧) / 时间戳名
pub fn resolve_snapshot_dir(cfg: &AppConfig, target: &str) -> Result<PathBuf> {
    let list = snapshot_dirs(cfg);
    if list.is_empty() {
        return Err(anyhow!("无快照"));
    }
    if target == "last" || target == "-1" {
        return Ok(list[0].clone());
    }
    if let Ok(n) = target.parse::<usize>() {
        if n >= 1 && n <= list.len() {
            return Ok(list[n - 1].clone());
        }
    }
    for p in &list {
        if p.file_name().map(|f| f.to_string_lossy() == target).unwrap_or(false) {
            return Ok(p.clone());
        }
    }
    Err(anyhow!("未找到快照: {}", target))
}

/// 给已有快照设置/修改备注，返回快照名
pub fn set_note(cfg: &AppConfig, target: &str, note: &str) -> Result<String> {
    let dir = resolve_snapshot_dir(cfg, target)?;
    write_note(&dir, note)?;
    Ok(dir.file_name().unwrap().to_string_lossy().to_string())
}

pub fn snapshot(cfg: &AppConfig) -> Result<String> {
    let log_dir = std::env::var("BY_MGR_LOG_DIR").unwrap_or_else(|_| {
            dirs::home_dir()
                .map(|h| h.join(".local/state/by-mgr").to_string_lossy().into_owned())
                .unwrap_or_else(|| "/tmp/by-mgr".to_string())
        });
    let _ = std::fs::create_dir_all(&log_dir);
    let log_file = format!("{}/tui-snapshot.log", log_dir);
    let _ = std::fs::write(&log_file, format!("[{}] Rust snapshot 调用 lib/snapshot.sh\n", chrono::Local::now().format("%H:%M:%S")));
    let path = cfg.lib_path("snapshot.sh");
    let out = std::process::Command::new("bash").arg(&path).env("BY_MGR_REPO", &cfg.repo_dir).output()?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    let _ = std::fs::OpenOptions::new().create(true).append(true).open(&log_file)
        .and_then(|mut f| std::io::Write::write_all(&mut f, format!("stderr: {}\nstdout: {}\nstatus: {}\n", stderr, stdout, out.status).as_bytes()));
    if !out.status.success() {
        anyhow::bail!("{}", stderr.trim().to_string() + &stdout);
    }
    // 最后一行 ✅ tag
    let tag = stdout.lines().rev().find(|l| l.contains("✅")).map(|l| l.replace("✅", "").trim().to_string()).unwrap_or_default();
    let files: Vec<&str> = stdout.lines().filter(|l| l.contains("->")).collect();
    let cnt = files.len();
    let tag_final = if tag.is_empty() {
        let mut list: Vec<_> = std::fs::read_dir(&cfg.backup_root).map(|it| it.flatten().map(|e| e.path()).collect::<Vec<_>>()).unwrap_or_default();
        list.sort();
        list.last().and_then(|p| p.file_name()).and_then(|n| n.to_str()).unwrap_or("").to_string()
    } else { tag };
    if cnt > 0 {
        Ok(format!("✅ 已备份 {} 文件 -> {}", cnt, tag_final))
    } else {
        Ok(format!("✅ {}", tag_final))
    }
}

pub fn snapshot_cli(cfg: &AppConfig, note: Option<&str>) -> Result<()> {
    // CLI 保留完整输出
    crate::core::run_lib(cfg, "snapshot.sh", &[])?;
    if let Some(n) = note {
        if !n.is_empty() {
            let list = snapshot_dirs(cfg);
            if let Some(dir) = list.first() {
                write_note(dir, n)?;
                println!("备注已保存: {}", n);
            }
        }
    }
    Ok(())
}

/// 快照完整性校验结果
pub struct VerifyReport {
    /// manifest 中的文件总数
    pub total: usize,
    /// 异常文件（哈希不符或缺失），格式同 manifest 中的路径
    pub bad: Vec<String>,
}

/// 按 manifest.txt 逐个重算 sha256 校验快照；无 manifest 时返回 None。
/// 以 LC_ALL=C 调用 sha256sum -c，保证输出可解析（不受 locale 影响）。
pub fn verify_snapshot(dir: &Path) -> Option<VerifyReport> {
    let manifest = dir.join("manifest.txt");
    if !manifest.is_file() {
        return None;
    }
    let total = std::fs::read_to_string(&manifest)
        .map(|s| s.lines().filter(|l| !l.trim().is_empty()).count())
        .unwrap_or(0);
    let out = std::process::Command::new("sha256sum")
        .args(["-c", "manifest.txt"])
        .current_dir(dir)
        .env("LC_ALL", "C")
        .output()
        .ok()?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let mut bad = Vec::new();
    for line in stdout.lines() {
        if line.contains(": FAILED") {
            bad.push(
                line.split(": FAILED")
                    .next()
                    .unwrap_or(line)
                    .trim()
                    .to_string(),
            );
        }
    }
    Some(VerifyReport { total, bad })
}

pub fn verify_cli(cfg: &AppConfig, target: Option<&str>) -> Result<()> {
    let dir = match target {
        Some(t) => resolve_snapshot_dir(cfg, t)?,
        None => snapshot_dirs(cfg)
            .into_iter()
            .next()
            .ok_or_else(|| anyhow::anyhow!("没有可校验的快照"))?,
    };
    let name = dir.file_name().unwrap().to_string_lossy().to_string();
    match verify_snapshot(&dir) {
        None => anyhow::bail!("快照 {} 没有文件清单（旧快照），无法校验", name),
        Some(rep) => {
            if rep.bad.is_empty() {
                println!("✅ 快照 {} 完整（{} 个文件全部通过校验）", name, rep.total);
                Ok(())
            } else {
                println!(
                    "❌ 快照 {} 有 {} 个文件异常（共 {} 个）:",
                    name,
                    rep.bad.len(),
                    rep.total
                );
                for b in &rep.bad {
                    println!("  {}", b);
                }
                anyhow::bail!("校验未通过")
            }
        }
    }
}

/// 读取快照 manifest 为 路径->哈希 映射（路径去掉 ./ 前缀）
fn read_manifest(dir: &Path) -> Option<std::collections::HashMap<String, String>> {
    let content = std::fs::read_to_string(dir.join("manifest.txt")).ok()?;
    let mut map = std::collections::HashMap::new();
    for line in content.lines() {
        let line = line.trim_end();
        if line.is_empty() {
            continue;
        }
        // 格式: <sha256><两个空格><路径>（文本模式）；二进制模式为 <空格>*<路径>
        let (hash, path) = line.split_once("  ")?;
        let path = path.trim_start_matches('*');
        let path = path.strip_prefix("./").unwrap_or(path);
        map.insert(path.to_string(), hash.trim().to_string());
    }
    Some(map)
}

pub fn diff_cli(cfg: &AppConfig, a: &str, b: Option<&str>) -> Result<()> {
    let dir_a = resolve_snapshot_dir(cfg, a)?;
    let dir_b = match b {
        Some(t) => resolve_snapshot_dir(cfg, t)?,
        None => snapshot_dirs(cfg)
            .into_iter()
            .next()
            .ok_or_else(|| anyhow::anyhow!("没有可对比的快照"))?,
    };
    if dir_a == dir_b {
        anyhow::bail!("两个快照是同一个，无需对比");
    }
    let name_a = dir_a.file_name().unwrap().to_string_lossy().to_string();
    let name_b = dir_b.file_name().unwrap().to_string_lossy().to_string();
    let ma = read_manifest(&dir_a)
        .ok_or_else(|| anyhow::anyhow!("快照 {} 没有文件清单，无法对比（旧快照）", name_a))?;
    let mb = read_manifest(&dir_b)
        .ok_or_else(|| anyhow::anyhow!("快照 {} 没有文件清单，无法对比（旧快照）", name_b))?;
    let mut added: Vec<&String> = mb.keys().filter(|k| !ma.contains_key(*k)).collect();
    let mut removed: Vec<&String> = ma.keys().filter(|k| !mb.contains_key(*k)).collect();
    let mut changed: Vec<&String> = ma
        .iter()
        .filter(|(k, h)| mb.get(*k).map(|h2| h2 != *h).unwrap_or(false))
        .map(|(k, _)| k)
        .collect();
    added.sort();
    removed.sort();
    changed.sort();
    println!("对比 {} → {}:", name_a, name_b);
    if added.is_empty() && removed.is_empty() && changed.is_empty() {
        println!("✅ 两个快照内容一致（共 {} 个文件）", ma.len());
        return Ok(());
    }
    for p in &added {
        println!("  + {}", p);
    }
    for p in &removed {
        println!("  - {}", p);
    }
    for p in &changed {
        println!("  ~ {}", p);
    }
    println!(
        "共 {} 新增 / {} 删除 / {} 变化",
        added.len(),
        removed.len(),
        changed.len()
    );
    Ok(())
}
