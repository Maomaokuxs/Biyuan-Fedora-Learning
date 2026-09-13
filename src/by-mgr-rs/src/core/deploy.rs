use anyhow::Result;
use crate::config::AppConfig;
use crate::core::run_lib;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DeployMode {
    Stow,
    Local,
}

pub fn deploy_cli(cfg: &AppConfig, mode: DeployMode) -> Result<()> {
    // 每次部署前同步至本地无仓存储
    let _ = init_local_share(cfg);
    // 执行前检查：stow 模式需先安装 stow
    if mode == DeployMode::Stow
        && std::process::Command::new("bash")
            .arg("-c")
            .arg("command -v stow >/dev/null 2>&1")
            .status()
            .map(|s| !s.success())
            .unwrap_or(true)
    {
        anyhow::bail!("stow 未安装，无法执行 stow 部署，请先执行: sudo dnf install -y stow");
    }
    let arg = match mode {
        DeployMode::Stow => "stow",
        DeployMode::Local => "local",
    };
    run_lib(cfg, "deploy.sh", &[arg])
}

pub fn deploy_cli_quiet(cfg: &AppConfig, mode: DeployMode) -> Result<String> {
    let _ = init_local_share(cfg);
    if mode == DeployMode::Stow
        && std::process::Command::new("bash")
            .arg("-c")
            .arg("command -v stow >/dev/null 2>&1")
            .status()
            .map(|s| !s.success())
            .unwrap_or(true)
    {
        anyhow::bail!("stow 未安装，请先执行: sudo dnf install -y stow");
    }
    let arg = match mode {
        DeployMode::Stow => "stow",
        DeployMode::Local => "local",
    };
    let path = cfg.lib_path("deploy.sh");
    let out = std::process::Command::new("bash")
        .arg(&path)
        .arg(arg)
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
        .find(|l| l.contains("部署完成"))
        .unwrap_or("✅ 部署完成")
        .trim()
        .to_string();
    if line.starts_with("✅") {
        Ok(line)
    } else {
        Ok(format!("✅ {}", line))
    }
}

pub fn deploy_interactive(cfg: &AppConfig) -> Result<()> {
    run_lib(cfg, "deploy.sh", &["stow"])
}

pub fn init_local_share(cfg: &AppConfig) -> Result<()> {
    let home = dirs::home_dir().ok_or_else(|| anyhow::anyhow!("无法获取 HOME"))?;
    let dst = home.join(".local/share/by-mgr");
    if cfg.repo_dir == dst {
        return Ok(());
    }
    std::fs::create_dir_all(&dst)?;
    for name in &["scripts", "config"] {
        let src = cfg.repo_dir.join(name);
        let dst_path = dst.join(name);
        if src.is_dir() {
            let _ = std::fs::remove_dir_all(&dst_path);
            crate::core::utils::copy_recursive(&src, &dst_path)?;
        }
    }
    // 仅保留 by-mgr 自身 dotfiles，非全量；清理旧全量
    let _ = std::fs::remove_dir_all(dst.join("dotfiles"));
    let src = cfg.repo_dir.join("dotfiles/by-mgr");
    let dst_path = dst.join("dotfiles/by-mgr");
    if src.is_dir() {
        std::fs::create_dir_all(dst_path.parent().unwrap())?;
        crate::core::utils::copy_recursive(&src, &dst_path)?;
    }
    // 同步当前二进制为实体文件（非软链，删仓后仍可用）
    let bin_dst = home.join(".local/bin/by-mgr");
    if let Ok(exe) = std::env::current_exe() {
        let exe_real = exe.canonicalize().unwrap_or(exe.clone());
        let _ = std::fs::create_dir_all(bin_dst.parent().unwrap());
        let _ = std::fs::remove_file(&bin_dst);
        let _ = std::fs::copy(&exe_real, &bin_dst);
        let _ = std::process::Command::new("chmod").arg("+x").arg(&bin_dst).status();
    }
    Ok(())
}
