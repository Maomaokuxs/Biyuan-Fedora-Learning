use anyhow::Result;
use crate::config::AppConfig;
use crate::core::run_lib;

pub fn restore_cli(cfg: &AppConfig, arg: Option<String>) -> Result<()> {
    // 还原前完整性提示：有清单但缺少自检通过标记的快照先警告
    if let Some(a) = &arg {
        if let Ok(dir) = crate::core::snapshot::resolve_snapshot_dir(cfg, a.as_str()) {
            if dir.join("manifest.txt").exists() && !dir.join(".bymgr-verified").exists() {
                eprintln!("⚠️ 该快照未通过完整性校验，还原结果可能不完整");
            }
        }
    }
    match arg {
        Some(a) => run_lib(cfg, "restore.sh", &[&a]),
        None => run_lib(cfg, "restore.sh", &[]),
    }
}

pub fn restore_interactive(cfg: &AppConfig) -> Result<()> {
    run_lib(cfg, "restore.sh", &[])
}

pub fn restore_cli_quiet(cfg: &AppConfig, arg: String) -> Result<String> {
    let path = cfg.lib_path("restore.sh");
    let out = std::process::Command::new("bash").arg(&path).arg(&arg).env("BY_MGR_QUIET", "1").env("BY_MGR_REPO", &cfg.repo_dir).output()?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    if !out.status.success() {
        anyhow::bail!("{}", stderr.trim().to_string() + &stdout);
    }
    // 解析 ✅ 行中的数量
    let cnt = stdout.lines().find(|l| l.contains("✅")).map(|l| l.split_whitespace().find(|s| s.parse::<usize>().is_ok()).unwrap_or("0")).unwrap_or("0");
    Ok(cnt.to_string())
}
