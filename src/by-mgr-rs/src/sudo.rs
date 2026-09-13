use anyhow::Result;
use std::process::Command;

pub fn guard(desc: &str) -> Result<()> {
    let status = Command::new("sudo").arg("-v").status()?;
    if !status.success() {
        anyhow::bail!("操作已取消（需要 sudo 权限）：{}", desc);
    }
    Ok(())
}

pub fn is_sudo_available() -> bool {
    Command::new("sudo").arg("-n").arg("true").status().map(|s| s.success()).unwrap_or(false)
}
