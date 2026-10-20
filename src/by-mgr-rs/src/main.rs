mod config;
mod core;
mod sudo;
mod ui;

use anyhow::Result;
use clap::{Parser, Subcommand};
use config::AppConfig;
use core::DeployMode;

#[derive(Parser)]
#[command(name = "by-mgr", version, about = "Biyuan 配置管理引擎 (Rust 重构版)", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// 文本模式（兼容旧 --text，不启动 TUI）
    #[arg(long, global = true)]
    text: bool,
}

#[derive(Subcommand)]
enum Commands {
    /// 创建快照
    Snapshot {
        /// 快照备注 (-m)
        #[arg(short = 'm', long = "message")]
        message: Option<String>,
    },
    /// 列出快照
    List,
    /// 历史还原
    Restore {
        /// 快照标识: last/-1/编号/时间戳 (YYYYMMDD_HHMMSS)
        target: Option<String>,
    },
    /// 给快照设置/修改备注
    Note {
        /// 快照标识: 编号/时间戳/last
        target: String,
        /// 备注内容
        message: String,
    },
    /// 清理快照
    Clean {
        /// 保留最近 N 个 (-k)
        #[arg(short = 'k')]
        keep: Option<usize>,
        /// 删除 N 天前的 (-d)
        #[arg(short = 'd')]
        days: Option<u64>,
    },
    /// 部署配置
    Deploy {
        /// 模式: stow | local (默认 stow)
        #[arg(default_value = "stow")]
        mode: String,
    },
    /// 仓库管理
    Repo {
        #[command(subcommand)]
        cmd: Option<RepoCmd>,
    },
    /// OTA 自更新
    #[command(alias = "update")]
    Ota,
}

#[derive(Subcommand)]
enum RepoCmd {
    /// 导出清单
    Export,
    /// 清理失效仓库
    Clean,
    /// 增量补齐
    Replenish,
    /// 编辑清单
    Edit,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    // Without subcommand: launch TUI if TTY, else help
    if cli.command.is_none() {
        if cli.text || !atty::is(atty::Stream::Stdout) {
            print_help();
            return Ok(());
        }
        let cfg = AppConfig::discover()?;
        ui::run_tui(cfg)?;
        return Ok(());
    }

    let cfg = AppConfig::discover()?;

    match cli.command.unwrap() {
        Commands::Snapshot { message } => {
            core::snapshot::snapshot_cli(&cfg, message.as_deref())?
        }
        Commands::List => {
            let list = core::snapshot::snapshot_dirs(&cfg);
            if list.is_empty() {
                println!("（无快照）");
            } else {
                println!(" {:<4} {:<17} {}", "编号", "时间", "备注");
                println!(" ---- ----------------- ----");
                for (i, p) in list.iter().enumerate() {
                    let note = core::snapshot::read_note(p)
                        .filter(|n| !n.is_empty())
                        .map(|n| {
                            if n.chars().count() > 30 {
                                format!("{}…", n.chars().take(30).collect::<String>())
                            } else {
                                n
                            }
                        })
                        .unwrap_or_else(|| "-".to_string());
                    println!(
                        " {:<4} {:<17} {}",
                        i + 1,
                        p.file_name().unwrap().to_string_lossy(),
                        note
                    );
                }
            }
        }
        Commands::Note { target, message } => {
            let name = core::snapshot::set_note(&cfg, &target, &message)?;
            println!("✅ {} 的备注已更新: {}", name, message);
        }
        Commands::Restore { target } => core::restore::restore_cli(&cfg, target)?,
        Commands::Clean { keep, days } => core::clean::clean_cli(&cfg, keep, days)?,
        Commands::Deploy { mode } => {
            let m = match mode.as_str() {
                "stow" => DeployMode::Stow,
                "local" | "physical" | "phys" => DeployMode::Local,
                _ => anyhow::bail!("未知部署模式: {} (可用 stow|local)", mode),
            };
            core::deploy::deploy_cli(&cfg, m)?;
        }
        Commands::Repo { cmd } => match cmd {
            None => core::repo::repo_manager(&cfg)?,
            Some(RepoCmd::Export) => core::repo::repo_export(&cfg)?,
            Some(RepoCmd::Clean) => core::repo::repo_clean(&cfg)?,
            Some(RepoCmd::Replenish) => core::repo::repo_replenish(&cfg)?,
            Some(RepoCmd::Edit) => core::repo::repo_edit(&cfg)?,
        },
        Commands::Ota => core::ota::ota(&cfg)?,
    }
    Ok(())
}

fn print_help() {
    println!("用法: by-mgr [COMMAND] [--text]");
    println!();
    println!("命令:");
    println!("  snapshot [-m 备注]      创建快照");
    println!("  note <编号> <备注>       给快照设置/修改备注");
    println!("  list                  列出快照");
    println!("  restore [TARGET]      历史还原 (last/-1/编号/时间戳)");
    println!("  clean -k <N> | -d <天数>  清理快照");
    println!("  deploy [stow|local]       部署配置");
    println!("  repo [export|clean|replenish|edit]  仓库管理");
    println!("  ota                   OTA 自更新");
    println!();
    println!("无参数时启动 TUI；--text 强制文本模式");
}
