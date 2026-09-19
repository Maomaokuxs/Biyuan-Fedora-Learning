use anyhow::Result;
use crate::config::AppConfig;
use crate::core::run_lib;

pub fn restore_cli(cfg: &AppConfig, arg: Option<String>) -> Result<()> {
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
    let out = std::process::Command::new("bash").arg(&path).arg(&arg).env("BY_MGR_QUIET", "1").output()?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    if !out.status.success() {
        anyhow::bail!("{}", stderr.trim().to_string() + &stdout);
    }
    // 解析 ✅ 行中的数量
    let cnt = stdout.lines().find(|l| l.contains("✅")).map(|l| l.split_whitespace().find(|s| s.parse::<usize>().is_ok()).unwrap_or("0")).unwrap_or("0");
    Ok(cnt.to_string())
}
