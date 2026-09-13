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
                    if cur.join("dotfiles").is_dir() {
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
        self.repo_dir.join("scripts/lib").join(name)
    }
}

/// 对应 bash get_target_path()
pub fn get_target_path(home: &Path, module: &str) -> PathBuf {
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
