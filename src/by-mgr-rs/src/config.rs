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
        // 仓库定位三级：自定义设定 > 智能寻找 > 无仓库模式
        // repo.state 扩展字段 mode=repo|local、source=config；旧记录（仅 id/path）按智能寻找处理
        let home0 = dirs::home_dir().ok_or_else(|| anyhow!("无法获取 HOME"))?;
        let state_path0 = home0.join(".config/by-mgr/repo.state");
        let state0 = read_repo_state_full(&state_path0);
        let first_time = state0.id.is_none() && state0.path.is_none() && state0.mode.is_none();
        let mut handled = false;
        let mut repo_dir_override: Option<PathBuf> = None;
        if state0.mode.as_deref() == Some("local") {
            // 无仓库模式（粘性）：跳过寻找，本地副本即真源，保障本地模式
            repo_dir_override = Some(home0.join(".local/share/by-mgr"));
            handled = true;
        } else if state0.source.as_deref() == Some("config") {
            // 自定义路径优先：设定什么用什么；身份只更新记录、不拦截
            if let Some(p) = state0.path.as_ref().map(|v| PathBuf::from(v)) {
                if p.join("dotfiles").is_dir() {
                    if let Some(cur_id) = read_repo_id(&p) {
                        if state0.id.as_deref() != Some(cur_id.as_str()) {
                            let mut st = state0.clone();
                            st.id = Some(cur_id);
                            st.path = Some(p.display().to_string());
                            st.mode = Some("repo".to_string());
                            let _ = write_repo_state_full(&state_path0, &st);
                        }
                    }
                    repo_dir_override = Some(p);
                    handled = true;
                }
            }
        }
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
        if let Some(p) = &repo_dir_override {
            repo_dir = p.clone();
        }

        // Try readlink for installed bin (~/.local/bin/by-mgr -> repo/scripts/by-mgr)
        if repo_dir_override.is_none() && !repo_dir.join("dotfiles").is_dir() {
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
        if repo_dir_override.is_none() && !repo_dir.join("dotfiles").is_dir() {
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
        if repo_dir_override.is_none() && !repo_dir.join("dotfiles").is_dir() {
            if let Some(p) = &env_repo {
                repo_dir = p.clone();
                used_env = true;
            }
        }
        // 本地无仓 fallback：~/.local/share/by-mgr
        if repo_dir_override.is_none() && !repo_dir.join("dotfiles").is_dir() {
            if let Some(home) = dirs::home_dir() {
                let local = home.join(".local/share/by-mgr");
                if local.join("dotfiles").is_dir() {
                    repo_dir = local;
                }
            }
        }
        // 首次运行（无任何记录）且在终端：寻找到的仓库先确认再落盘为设定；
        // 没找到则告知并落盘无仓库模式。非终端环境不询问、不落盘，沿用本次定位结果。
        if !handled && first_time && atty::is(atty::Stream::Stdin) {
            handled = true;
            if read_repo_id(&repo_dir).is_some() {
                let yes = confirm_first_repo(&repo_dir);
                eprintln!("   变更仓库: by-mgr where <新路径>；无仓库模式: by-mgr where --local；恢复智能寻找: by-mgr where --auto");
                if yes {
                    let mut st = state0.clone();
                    st.id = read_repo_id(&repo_dir);
                    st.path = Some(repo_dir.display().to_string());
                    st.mode = Some("repo".to_string());
                    st.source = Some("config".to_string());
                    let _ = write_repo_state_full(&state_path0, &st);
                } else {
                    let mut st = state0.clone();
                    st.mode = Some("local".to_string());
                    st.source = Some("config".to_string());
                    let _ = write_repo_state_full(&state_path0, &st);
                    repo_dir = home0.join(".local/share/by-mgr");
                }
            } else {
                eprintln!(">> 未找到 by-mgr 仓库，将使用无仓库模式（本地模式不受影响）");
                eprintln!("   以后添加仓库: by-mgr where <仓库路径>；查看当前模式: by-mgr where");
                let mut st = state0.clone();
                st.mode = Some("local".to_string());
                st.source = Some("config".to_string());
                let _ = write_repo_state_full(&state_path0, &st);
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
        if !handled && used_env {
            eprintln!("使用 BY_MGR_REPO 指定的仓库: {}", repo_dir.display());
        } else if !handled {
            if let Some(p) = &env_repo {
                let canon = |x: &Path| x.canonicalize().unwrap_or_else(|_| x.to_path_buf());
                if canon(p) != canon(&repo_dir) {
                    eprintln!(
                        "注意: BY_MGR_REPO 指向 {}，与二进制所在仓库 {} 不一致，已采用后者",
                        p.display(),
                        repo_dir.display()
                    );
                }
            }
        }

        // 仓库身份核对：.by-mgr-root 中的 id 与本地记录（repo.state）比对。
        // 同 id 换路径 = 仓库搬家：提示并更新记录；id 不同 = 换了仓库：停机让用户确认。
        let cur_id_opt = if handled { None } else { read_repo_id(&repo_dir) };
        if let Some(cur_id) = cur_id_opt {
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

/// repo.state 全部字段（旧文件只有 id/path，其余缺省按智能寻找处理）
#[derive(Debug, Clone, Default)]
pub struct RepoState {
    pub id: Option<String>,
    pub path: Option<String>,
    pub mode: Option<String>,
    pub source: Option<String>,
}

pub fn read_repo_state_full(path: &Path) -> RepoState {
    let mut st = RepoState::default();
    if let Ok(content) = std::fs::read_to_string(path) {
        for line in content.lines() {
            let line = line.trim();
            if let Some(v) = line.strip_prefix("id=") {
                st.id = Some(v.trim().to_string());
            } else if let Some(v) = line.strip_prefix("path=") {
                st.path = Some(v.trim().to_string());
            } else if let Some(v) = line.strip_prefix("mode=") {
                st.mode = Some(v.trim().to_string());
            } else if let Some(v) = line.strip_prefix("source=") {
                st.source = Some(v.trim().to_string());
            }
        }
    }
    st
}

pub fn write_repo_state_full(path: &Path, st: &RepoState) -> Result<()> {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let mut out = String::new();
    if let Some(v) = &st.id {
        out += &format!("id={}\n", v);
    }
    if let Some(v) = &st.path {
        out += &format!("path={}\n", v);
    }
    if let Some(v) = &st.mode {
        out += &format!("mode={}\n", v);
    }
    if let Some(v) = &st.source {
        out += &format!("source={}\n", v);
    }
    std::fs::write(path, out)?;
    Ok(())
}

pub fn repo_state_path() -> PathBuf {
    dirs::home_dir()
        .map(|h| h.join(".config/by-mgr/repo.state"))
        .unwrap_or_else(|| PathBuf::from(".config/by-mgr/repo.state"))
}

pub fn repo_id_of(dir: &Path) -> Option<String> {
    read_repo_id(dir)
}

/// 首次运行确认：智能寻找到的仓库先经用户确认再落盘为设定
fn confirm_first_repo(repo_dir: &Path) -> bool {
    eprintln!(">> 首次运行，智能寻找到 by-mgr 仓库:");
    eprintln!("   {}", repo_dir.display());
    eprint!("   使用这个仓库吗？[Y/n] ");
    use std::io::Write;
    let _ = std::io::stderr().flush();
    let mut line = String::new();
    match std::io::stdin().read_line(&mut line) {
        Ok(_) => {
            let a = line.trim().to_lowercase();
            a.is_empty() || a == "y" || a == "yes"
        }
        Err(_) => true,
    }
}
