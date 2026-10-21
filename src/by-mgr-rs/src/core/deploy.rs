use anyhow::Result;
use crate::config::AppConfig;
use crate::core::run_lib;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DeployMode {
    Stow,
    Local,
}

pub fn deploy_cli(cfg: &AppConfig, mode: DeployMode, force: bool) -> Result<()> {
    // --force: 跳过部署前快照（透传给 deploy.sh）
    if force {
        std::env::set_var("BY_MGR_FORCE", "1");
    }
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
        .env("BY_MGR_QUIET", "1").env("BY_MGR_REPO", &cfg.repo_dir)
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
    // 同步仓库内容到本地无仓存储（删仓后仍可运作的副本）；
    // 目标已是软链时跳过（如开发测试的链接布局），不冲掉链接
    for name in &["scripts", "config", "dotfiles"] {
        let src = cfg.repo_dir.join(name);
        let dst_path = dst.join(name);
        if src.is_dir() && !dst_path.is_symlink() {
            let _ = crate::core::trash::trash_move(cfg, &dst_path, "deploy");
            crate::core::utils::copy_recursive(&src, &dst_path)?;
        }
    }
    // lib 脚本同样播种实体副本（源码在 src/by-mgr-rs/lib）
    let lib_src = cfg.repo_dir.join("src/by-mgr-rs/lib");
    let lib_dst = dst.join("lib");
    if lib_src.is_dir() && !lib_dst.is_symlink() {
        let _ = crate::core::trash::trash_move(cfg, &lib_dst, "deploy");
        crate::core::utils::copy_recursive(&lib_src, &lib_dst)?;
    }
    // by-mgr 独立目录：~/.config/by-mgr 实目录，不再 stow 链接
    let _ = std::fs::remove_file(home.join(".config/by-mgr"));
    let _ = std::fs::create_dir_all(home.join(".config/by-mgr"))?;
    let _ = std::fs::create_dir_all(home.join(".config/by-mgr/templates"))?;
    let src_tpl = cfg.repo_dir.join("dotfiles/by-mgr/.config/by-mgr/templates");
    if src_tpl.is_dir() {
        if let Ok(rd) = std::fs::read_dir(&src_tpl) {
            for entry in rd.filter_map(|e| e.ok()) {
                let _ = std::fs::copy(
                    entry.path(),
                    home.join(".config/by-mgr/templates").join(entry.file_name()),
                );
            }
        }
    }
    // 同步当前二进制为实体文件（非软链，删仓后仍可用）
    // bin 已是软链（如链接到仓库构建产物）时跳过，避免冲掉链接
    let bin_dst = home.join(".local/bin/by-mgr");
    if !bin_dst.is_symlink() {
        if let Ok(exe) = std::env::current_exe() {
            let exe_real = exe.canonicalize().unwrap_or(exe.clone());
            let _ = std::fs::create_dir_all(bin_dst.parent().unwrap());
            let _ = crate::core::trash::trash_move(cfg, &bin_dst, "deploy");
            let _ = std::fs::copy(&exe_real, &bin_dst);
            let _ = std::process::Command::new("chmod").arg("+x").arg(&bin_dst).status();
        }
    }
    Ok(())
}
