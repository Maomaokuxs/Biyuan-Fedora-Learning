use anyhow::Result;
use crate::config::AppConfig;
use crate::core::run_lib;

pub fn editor_settings(cfg: &AppConfig) -> Result<()> {
    run_lib(cfg, "editor.sh", &[])
}

pub fn editor_set(cfg: &AppConfig, ed: &str) -> Result<()> {
    run_lib(cfg, "editor.sh", &[ed])
}

pub fn editor_quiet(cfg: &AppConfig, ed: &str) -> Result<String> {
    let path = cfg.lib_path("editor.sh");
    let out = std::process::Command::new("bash").arg(&path).arg(ed).env("BY_MGR_QUIET", "1").output()?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    if !out.status.success() {
        anyhow::bail!("{}", stderr.trim().to_string() + &stdout);
    }
    let line = stdout.lines().rev().find(|l| l.contains("✅") || l.contains("已设置")).unwrap_or("✅ 已设置").trim().to_string();
    if line.starts_with('✅') { Ok(line) } else { Ok(format!("✅ {}", line)) }
}
