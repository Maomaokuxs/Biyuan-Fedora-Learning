pub mod snapshot;
pub mod restore;
pub mod clean;
pub mod deploy;
pub mod ota;
pub mod repo;
pub mod editor;
pub mod display;
pub mod utils;

pub use snapshot::snapshot;
pub use restore::{restore_interactive, restore_cli};
pub use clean::{clean_cli, clean_interactive};
pub use deploy::{deploy_cli, deploy_interactive, DeployMode};
pub use ota::{ota, ota_quiet};
pub use repo::{repo_manager, repo_export_quiet, repo_clean_quiet, repo_replenish_quiet, repo_clean_progress};
pub use editor::{editor_settings, editor_quiet};
pub use display::display_manager;

use anyhow::{anyhow, Result};
use crate::config::AppConfig;
use std::process::Command;

pub fn run_lib(cfg: &AppConfig, script: &str, args: &[&str]) -> Result<()> {
    let path = cfg.lib_path(script);
    if !path.is_file() {
        return Err(anyhow!("lib 脚本缺失: {}", path.display()));
    }
    let status = Command::new("bash").arg(&path).args(args).status()?;
    if !status.success() {
        return Err(anyhow!("{} 执行失败 (exit {:?})", script, status.code()));
    }
    Ok(())
}
