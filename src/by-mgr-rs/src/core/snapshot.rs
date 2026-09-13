use anyhow::Result;
use crate::config::AppConfig;
use crate::core::run_lib;

pub fn snapshot(cfg: &AppConfig) -> Result<String> {
    let log_dir = std::env::var("BY_MGR_LOG_DIR").unwrap_or_else(|_| "/tmp/by-mgr".to_string());
    let _ = std::fs::create_dir_all(&log_dir);
    let log_file = format!("{}/tui-snapshot.log", log_dir);
    let _ = std::fs::write(&log_file, format!("[{}] Rust snapshot 调用 lib/snapshot.sh\n", chrono::Local::now().format("%H:%M:%S")));
    let path = cfg.lib_path("snapshot.sh");
    let out = std::process::Command::new("bash").arg(&path).output()?;
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

pub fn snapshot_cli(cfg: &AppConfig) -> Result<()> {
    // CLI 保留完整输出
    crate::core::run_lib(cfg, "snapshot.sh", &[])
}
