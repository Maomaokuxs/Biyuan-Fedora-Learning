use anyhow::Result;
use crate::config::AppConfig;
use crate::core::run_lib;

pub fn ota(cfg: &AppConfig) -> Result<()> {
    run_lib(cfg, "ota.sh", &[])
}

pub fn ota_quiet(cfg: &AppConfig) -> Result<String> {
    let path = cfg.lib_path("ota.sh");
    let out = std::process::Command::new("bash")
        .arg(&path)
        .env("BY_MGR_QUIET", "1")
        .output()?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    if !out.status.success() {
        anyhow::bail!("{}", stderr.trim().to_string() + &stdout);
    }
    let line = stdout
        .lines()
        .rev()
        .find(|l| l.contains("OTA") || l.contains("更新成功"))
        .unwrap_or("✅ OTA 更新成功")
        .trim()
        .to_string();
    if line.starts_with('✅') || line.starts_with('✨') {
        Ok(line)
    } else {
        Ok(format!("✅ {}", line))
    }
}
