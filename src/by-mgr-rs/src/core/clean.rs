use anyhow::Result;
use crate::config::AppConfig;
use crate::core::run_lib;

pub fn clean_cli(cfg: &AppConfig, keep: Option<usize>, days: Option<u64>) -> Result<()> {
    if let Some(k) = keep {
        run_lib(cfg, "clean.sh", &["-k", &k.to_string()])
    } else if let Some(d) = days {
        run_lib(cfg, "clean.sh", &["-d", &d.to_string()])
    } else {
        Err(anyhow::anyhow!("用法: by-mgr clean -k <N> 或 by-mgr clean -d <天数>"))
    }
}

pub fn clean_cli_quiet(cfg: &AppConfig, keep: Option<usize>, days: Option<u64>) -> Result<String> {
    let (args, mode) = if let Some(k) = keep {
        (vec!["-k".to_string(), k.to_string()], "k")
    } else if let Some(d) = days {
        (vec!["-d".to_string(), d.to_string()], "d")
    } else {
        anyhow::bail!("用法: by-mgr clean -k <N> 或 by-mgr clean -d <天数>");
    };
    let path = cfg.lib_path("clean.sh");
    let args_ref: Vec<&str> = args.iter().map(|s| s.as_str()).collect();
    let out = std::process::Command::new("bash").arg(&path).args(&args_ref).env("BY_MGR_QUIET", "1").output()?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    if !out.status.success() {
        anyhow::bail!("{}", stderr.trim().to_string() + &stdout);
    }
    // 仅保留最终一行，避免终端溢出，TUI 仅在底部状态栏显示
    let raw = stdout.lines().filter(|l| l.contains("已清理")).next().unwrap_or("").trim().to_string();
    if raw.is_empty() {
        Ok("✅ 清理完成".to_string())
    } else if raw.starts_with("✅") {
        Ok(raw)
    } else {
        Ok(format!("✅ {}", raw))
    }
}

pub fn clean_interactive(cfg: &AppConfig) -> Result<()> {
    run_lib(cfg, "clean.sh", &[])
}
