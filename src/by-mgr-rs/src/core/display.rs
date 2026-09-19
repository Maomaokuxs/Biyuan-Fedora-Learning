use anyhow::Result;
use crate::config::AppConfig;
use crate::core::run_lib;
pub fn display_manager(cfg: &AppConfig) -> Result<String> {
    run_lib(cfg, "display.sh", &[])?;
    Ok("✅ 显示器管理完成".to_string())
}
