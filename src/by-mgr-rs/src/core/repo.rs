use anyhow::Result;
use crate::config::AppConfig;
use crate::core::run_lib;

pub fn repo_manager(cfg: &AppConfig) -> Result<()> {
    run_lib(cfg, "repo.sh", &["menu"])
}

pub fn repo_export(cfg: &AppConfig) -> Result<()> { run_lib(cfg, "repo.sh", &["export"]) }
pub fn repo_clean(cfg: &AppConfig) -> Result<()> { run_lib(cfg, "repo.sh", &["clean"]) }
pub fn repo_replenish(cfg: &AppConfig) -> Result<()> { run_lib(cfg, "repo.sh", &["replenish"]) }
pub fn repo_edit(cfg: &AppConfig) -> Result<()> { run_lib(cfg, "repo.sh", &["edit"]) }

fn repo_quiet(cfg: &AppConfig, arg: &str) -> Result<String> {
    let path = cfg.lib_path("repo.sh");
    let out = std::process::Command::new("bash").arg(&path).arg(arg).env("BY_MGR_QUIET", "1").output()?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    if !out.status.success() {
        anyhow::bail!("{}", stderr.trim().to_string() + &stdout);
    }
    let line = stdout.lines().rev().find(|l| l.contains("✅") || l.contains("已导出") || l.contains("清理完成") || l.contains("补齐完成")).unwrap_or("✅ 完成").trim().to_string();
    if line.starts_with('✅') { Ok(line) } else { Ok(format!("✅ {}", line)) }
}
pub fn repo_export_quiet(cfg: &AppConfig) -> Result<String> { repo_quiet(cfg, "export") }
pub fn repo_clean_quiet(cfg: &AppConfig) -> Result<String> { repo_quiet(cfg, "clean") }
pub fn repo_replenish_quiet(cfg: &AppConfig) -> Result<String> { repo_quiet(cfg, "replenish") }

pub fn repo_clean_progress<F>(_cfg: &AppConfig, mut on_progress: F) -> Result<String>
where
    F: FnMut(usize, usize, &str),
{
    // 列出启用的仓库
    let out = std::process::Command::new("bash")
        .arg("-c")
        .arg("dnf repolist --enabled 2>/dev/null | tail -n +2 | awk '{print $1}'")
        .output()?;
    let list = String::from_utf8_lossy(&out.stdout);
    let ids: Vec<String> = list.lines().filter(|l| !l.trim().is_empty() && !l.starts_with("Repo")).map(|s| s.trim().to_string()).collect();
    let total = ids.len();
    if total == 0 {
        return Ok("✅ 无仓库需检查".to_string());
    }
    let mut failed = 0;
    for (i, id) in ids.iter().enumerate() {
        on_progress(i, total, id);
        let ok = std::process::Command::new("bash")
            .arg("-c")
            .arg(format!("dnf --disablerepo='*' --enablerepo='{}' makecache --refresh &>/dev/null", id))
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if !ok {
            failed += 1;
            let _ = std::process::Command::new("bash")
                .arg("-c")
                .arg(format!(
                    "if command -v dnf5 &>/dev/null; then sudo dnf config-manager setopt {}.enabled=0 2>/dev/null; else sudo dnf config-manager --set-disabled {} 2>/dev/null; fi",
                    id, id
                ))
                .status();
        }
        on_progress(i + 1, total, id);
    }
    if failed == 0 {
        Ok("✅ 清理完成，无失效仓库".to_string())
    } else {
        Ok(format!("✅ 清理完成，禁用 {} 个失效仓库", failed))
    }
}
