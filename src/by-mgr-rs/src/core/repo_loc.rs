use anyhow::Result;
use std::path::PathBuf;

/// repo.state 里的仓库定位（config.rs 的 RepoState）决定模式：
/// mode=local 为无仓库模式（粘性）；source=config 且 path 有效为自定义路径；
/// 否则（含旧版仅 id/path 的记录）走智能寻找，与原行为一致。
pub fn where_cli(path: Option<&str>, local: bool, auto: bool) -> Result<()> {
    use crate::config::{read_repo_state_full, repo_id_of, repo_state_path, write_repo_state_full, RepoState};
    let sp = repo_state_path();
    let actions = path.is_some() as u8 + local as u8 + auto as u8;
    if actions > 1 {
        anyhow::bail!("用法: by-mgr where [<路径>|--local|--auto]（三者只能选一）");
    }
    if auto {
        let _ = std::fs::remove_file(&sp);
        println!("已清除仓库设定，下次运行将重新智能寻找（并在终端中请你确认）。");
        return Ok(());
    }
    if local {
        let mut st = read_repo_state_full(&sp);
        st.mode = Some("local".to_string());
        st.source = Some("config".to_string());
        write_repo_state_full(&sp, &st)?;
        println!("已切换到无仓库模式：后续运行跳过仓库寻找，使用本地副本（本地模式不受影响）。");
        println!("切回仓库: by-mgr where <仓库路径>");
        return Ok(());
    }
    if let Some(p) = path {
        let dir = PathBuf::from(p);
        if !dir.join(".by-mgr-root").is_file() || !dir.join("dotfiles").is_dir() {
            anyhow::bail!("{} 不是有效的 by-mgr 仓库（缺少 .by-mgr-root 或 dotfiles/）", dir.display());
        }
        let canon = dir.canonicalize().unwrap_or(dir);
        let mut st = RepoState::default();
        st.id = repo_id_of(&canon);
        st.path = Some(canon.display().to_string());
        st.mode = Some("repo".to_string());
        st.source = Some("config".to_string());
        write_repo_state_full(&sp, &st)?;
        println!("已设定仓库: {}", canon.display());
        return Ok(());
    }
    // 查看当前定位
    let st = read_repo_state_full(&sp);
    if st.mode.as_deref() == Some("local") {
        println!("当前模式: 无仓库模式（本地模式）");
        if let Some(h) = dirs::home_dir() {
            println!("本地目录: {}", h.join(".local/share/by-mgr").display());
        }
        if let Some(p) = &st.path {
            println!("记录中的仓库: {}（切回: by-mgr where {}）", p, p);
        }
    } else if st.source.as_deref() == Some("config") {
        println!("当前模式: 仓库模式（自定义路径）");
        println!("仓库路径: {}", st.path.as_deref().unwrap_or("-"));
        if let Some(id) = &st.id {
            println!("仓库 id: {}", id);
        }
    } else if st.path.is_some() {
        println!("当前模式: 仓库模式（智能寻找）");
        println!("上次使用: {}", st.path.as_deref().unwrap_or("-"));
        if let Some(id) = &st.id {
            println!("仓库 id: {}", id);
        }
    } else {
        println!("当前模式: 尚未设定（下次运行将智能寻找，并在终端中请你确认）");
    }
    println!("变更方法:");
    println!("  by-mgr where <路径>    设定自定义仓库路径");
    println!("  by-mgr where --local   切换到无仓库模式（保障本地模式使用）");
    println!("  by-mgr where --auto    清除设定，恢复智能寻找");
    Ok(())
}
