use anyhow::Result;
use crate::config::AppConfig;
use crate::core::run_lib;

pub fn restore_cli(cfg: &AppConfig, arg: Option<String>, force: bool) -> Result<()> {
    // 还原前完整性校验：有清单的快照先按 manifest 真校验，异常默认中止（--force 放行）
    if let Some(a) = &arg {
        if let Ok(dir) = crate::core::snapshot::resolve_snapshot_dir(cfg, a.as_str()) {
            match crate::core::snapshot::verify_snapshot(&dir) {
                Some(rep) => {
                    if !rep.bad.is_empty() {
                        if force {
                            eprintln!(
                                "⚠️ 快照校验有 {} 个文件异常，已按 --force 继续还原",
                                rep.bad.len()
                            );
                        } else {
                            anyhow::bail!(
                                "快照校验未通过（{} 个文件异常），已中止还原。详情: by-mgr verify {}；确需还原加 --force",
                                rep.bad.len(),
                                a
                            );
                        }
                    }
                }
                None => {
                    eprintln!("⚠️ 该快照没有文件清单（旧快照），无法校验完整性");
                }
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
