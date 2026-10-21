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
    let out = std::process::Command::new("bash").arg(&path).arg(arg).env("BY_MGR_QUIET", "1").env("BY_MGR_REPO", &cfg.repo_dir).output()?;
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
    // 列出启用的仓库：直接调用 dnf 并在 Rust 侧解析（不经 shell 拼接，杜绝注入）
    let out = std::process::Command::new("dnf")
        .args(["repolist", "--enabled"])
        .output()?;
    let list = String::from_utf8_lossy(&out.stdout);
    let ids: Vec<String> = list
        .lines()
        .skip(1)
        .filter_map(|l| l.split_whitespace().next())
        .filter(|s| !s.is_empty() && !s.starts_with("Repo"))
        .map(|s| s.to_string())
        .collect();
    let total = ids.len();
    if total == 0 {
        return Ok("✅ 无仓库需检查".to_string());
    }
    let is_dnf5 = std::process::Command::new("dnf5")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
        || std::process::Command::new("dnf")
            .arg("--version")
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).contains("dnf5"))
            .unwrap_or(false);
    let mut failed = 0;
    for (i, id) in ids.iter().enumerate() {
        on_progress(i, total, id);
        let ok = std::process::Command::new("dnf")
            .args([
                "--disablerepo=*",
                &format!("--enablerepo={}", id),
                "--setopt=skip_if_unavailable=False",
                "makecache",
                "--refresh",
            ])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if !ok {
            failed += 1;
            if is_dnf5 {
                let _ = std::process::Command::new("sudo")
                    .args(["dnf", "config-manager", "setopt", &format!("{}.enabled=0", id)])
                    .status();
            } else {
                let _ = std::process::Command::new("sudo")
                    .args(["dnf", "config-manager", "--set-disabled", id])
                    .status();
            }
        }
        on_progress(i + 1, total, id);
    }
    if failed == 0 {
        Ok("✅ 清理完成，无失效仓库".to_string())
    } else {
        Ok(format!("✅ 清理完成，禁用 {} 个失效仓库", failed))
    }
}
