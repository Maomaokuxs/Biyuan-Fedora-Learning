use anyhow::{anyhow, Result};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct AppConfig {
    pub repo_dir: PathBuf,
    pub dotfiles_dir: PathBuf,
    pub backup_root: PathBuf,
    pub self_path: PathBuf,
    pub user_config_dir: PathBuf,
}

impl AppConfig {
    pub fn discover() -> Result<Self> {
        let self_path = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("/proc/self/exe"));
        let exe_canonical = self_path.canonicalize().unwrap_or(self_path.clone());
        // BY_MGR_REPO 仅登记待用（须通过身份校验：标记 + dotfiles）；
        // 定位优先级：exe 自身位置 > BY_MGR_REPO 兜底 > 本地无仓目录
        let env_repo = std::env::var("BY_MGR_REPO")
            .ok()
            .map(|v| PathBuf::from(v.trim()))
            .filter(|p| p.join(".by-mgr-root").is_file() && p.join("dotfiles").is_dir());
        let mut used_env = false;
        let mut repo_dir = exe_canonical
            .parent()
            .and_then(|p| p.parent())
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| PathBuf::from("."));

        // Try readlink for installed bin (~/.local/bin/by-mgr -> repo/scripts/by-mgr)
        if !repo_dir.join("dotfiles").is_dir() {
            if let Ok(real) = std::fs::read_link(&exe_canonical) {
                let cand = real.parent().and_then(|p| p.parent()).map(|p| p.to_path_buf());
                if let Some(c) = cand {
                    if c.join("dotfiles").is_dir() {
                        repo_dir = c;
                    }
                }
            }
        }
        // Dev fallback: walk up from exe dir and cwd up to 5 levels (cargo target/debug case)
        if !repo_dir.join("dotfiles").is_dir() {
            for base in [exe_canonical.parent().map(|p| p.to_path_buf()), std::env::current_dir().ok()].into_iter().flatten() {
                let mut cur = base.clone();
                for _ in 0..6 {
                    if cur.join(".by-mgr-root").is_file() && cur.join("dotfiles").is_dir() {
                        repo_dir = cur.clone();
                        break;
                    }
                    if let Some(parent) = cur.parent() {
                        cur = parent.to_path_buf();
                    } else {
                        break;
                    }
                }
                if repo_dir.join("dotfiles").is_dir() {
                    break;
                }
            }
        }
        // exe 定位失败时才采用 BY_MGR_REPO
        if !repo_dir.join("dotfiles").is_dir() {
            if let Some(p) = &env_repo {
                repo_dir = p.clone();
                used_env = true;
            }
        }
        // 本地无仓 fallback：~/.local/share/by-mgr
        if !repo_dir.join("dotfiles").is_dir() {
            if let Some(home) = dirs::home_dir() {
                let local = home.join(".local/share/by-mgr");
                if local.join("dotfiles").is_dir() {
                    repo_dir = local;
                }
            }
        }
        let dotfiles_dir = repo_dir.join("dotfiles");
        if !dotfiles_dir.is_dir() {
            return Err(anyhow!(
                "无法定位 dotfiles 目录，推算仓库根为: {} (可重建: by-mgr deploy --init-local)",
                repo_dir.display()
            ));
        }

        let home = dirs::home_dir().ok_or_else(|| anyhow!("无法获取 HOME"))?;
        let backup_root = home.join(".config/by-mgr/backup");
        let user_config_dir = home.join(".config/by-mgr");

        // BY_MGR_REPO 实际生效或与 exe 定位冲突时给出提示，避免静默用错仓库
        if used_env {
            eprintln!("使用 BY_MGR_REPO 指定的仓库: {}", repo_dir.display());
        } else if let Some(p) = &env_repo {
            let canon = |x: &Path| x.canonicalize().unwrap_or_else(|_| x.to_path_buf());
            if canon(p) != canon(&repo_dir) {
                eprintln!(
                    "注意: BY_MGR_REPO 指向 {}，与二进制所在仓库 {} 不一致，已采用后者",
                    p.display(),
                    repo_dir.display()
                );
            }
        }

        // 仓库身份核对：.by-mgr-root 中的 id 与本地记录（repo.state）比对。
        // 同 id 换路径 = 仓库搬家：提示并更新记录；id 不同 = 换了仓库：停机让用户确认。
        if let Some(cur_id) = read_repo_id(&repo_dir) {
            let state_path = user_config_dir.join("repo.state");
            match read_repo_state(&state_path) {
                None => {
                    let _ = std::fs::create_dir_all(&user_config_dir);
                    let _ = std::fs::write(
                        &state_path,
                        format!("id={}\npath={}\n", cur_id, repo_dir.display()),
                    );
                }
                Some((old_id, old_path)) => {
                    if old_id != cur_id {
                        return Err(anyhow!(
                            "仓库身份已变更，停止运行以防用错仓库。\n  记录中的仓库: {} ({})\n  当前定位到的: {} ({})\n若确实更换了仓库，请删除 {} 后重试。",
                            old_path,
                            old_id,
                            repo_dir.display(),
                            cur_id,
                            state_path.display()
                        ));
                    }
                    if old_path != repo_dir.display().to_string() {
                        eprintln!("仓库位置已变更: {} -> {}", old_path, repo_dir.display());
                        let _ = std::fs::write(
                            &state_path,
                            format!("id={}\npath={}\n", cur_id, repo_dir.display()),
                        );
                    }
                }
            }
        }

        Ok(Self {
            repo_dir,
            dotfiles_dir,
            backup_root,
            self_path: exe_canonical,
            user_config_dir,
        })
    }

    pub fn dotfiles_modules(&self) -> Vec<String> {
        let mut mods = Vec::new();
        if let Ok(entries) = std::fs::read_dir(&self.dotfiles_dir) {
            for e in entries.flatten() {
                if let Ok(ft) = e.file_type() {
                    if ft.is_dir() {
                        if let Some(name) = e.file_name().to_str() {
                            mods.push(name.to_string());
                        }
                    }
                }
            }
        }
        mods.sort();
        mods
    }

    pub fn lib_path(&self, name: &str) -> std::path::PathBuf {
        let local = dirs::home_dir().unwrap().join(".local/share/by-mgr/lib").join(name);
        if local.exists() { local } else { self.repo_dir.join("src/by-mgr-rs/lib").join(name) }
    }
}

/// 对应 bash get_target_path()；先查 dotfiles/.bymgr-paths 覆盖表（模块名=相对HOME路径）
pub fn get_target_path(cfg: &AppConfig, module: &str) -> PathBuf {
    let home = home_dir().unwrap_or_default();
    let table = cfg.dotfiles_dir.join(".bymgr-paths");
    if let Ok(content) = std::fs::read_to_string(&table) {
        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((name, rel)) = line.split_once('=') {
                if name.trim() == module {
                    return home.join(rel.trim());
                }
            }
        }
    }
    let base = home.join(".config").join(module);
    if !base.is_dir() && home.join(format!(".config/{}.toml", module)).is_file() {
        home.join(format!(".config/{}.toml", module))
    } else if !base.is_dir() && home.join(format!(".config/{}.conf", module)).is_file() {
        home.join(format!(".config/{}.conf", module))
    } else {
        // special bash mapping
        if module == "bash" {
            home.join(".bashrc")
        } else {
            base
        }
    }
}

pub fn home_dir() -> Result<PathBuf> {
    dirs::home_dir().ok_or_else(|| anyhow!("无法获取 HOME 目录"))
}

/// 读取仓库根标记中的 id（无 id 返回 None：旧标记/无仓模式，跳过身份核对）
fn read_repo_id(repo_dir: &Path) -> Option<String> {
    let content = std::fs::read_to_string(repo_dir.join(".by-mgr-root")).ok()?;
    content
        .lines()
        .filter_map(|l| l.trim().strip_prefix("id="))
        .map(|s| s.trim().to_string())
        .next()
        .filter(|s| !s.is_empty())
}

/// 读取本地记录的仓库身份（repo.state：id= / path= 两行）
fn read_repo_state(path: &Path) -> Option<(String, String)> {
    let content = std::fs::read_to_string(path).ok()?;
    let mut id = None;
    let mut p = None;
    for line in content.lines() {
        let line = line.trim();
        if let Some(v) = line.strip_prefix("id=") {
            id = Some(v.trim().to_string());
        } else if let Some(v) = line.strip_prefix("path=") {
            p = Some(v.trim().to_string());
        }
    }
    Some((id?, p?))
}
