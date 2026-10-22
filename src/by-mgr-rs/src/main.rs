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
        /// 跳过完整性校验强行还原
        #[arg(long)]
        force: bool,
    },
    /// 校验快照完整性（按清单重算哈希）
    Verify {
        /// 快照标识: 编号/时间戳/last（缺省为最新）
        target: Option<String>,
    },
    /// 对比两个快照的文件差异
    Diff {
        /// 快照 A: 编号/时间戳/last
        a: String,
        /// 快照 B（缺省为最新）
        b: Option<String>,
    },
    /// 给快照设置/修改备注
    Note {
        /// 快照标识: 编号/时间戳/last
        target: String,
        /// 备注内容
        message: String,
    },
    /// 回收站
    Trash {
        #[command(subcommand)]
        cmd: Option<TrashCmd>,
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
        /// 模式: stow | local (必须明确指定，无默认)
        mode: Option<String>,
        /// 跳过部署前快照，直接部署
        #[arg(long)]
        force: bool,
    },
    /// 仓库管理
    Repo {
        #[command(subcommand)]
        cmd: Option<RepoCmd>,
    },
    /// OTA 自更新
    #[command(alias = "update")]
    Ota,
    /// 查看/设定仓库位置与模式
    Where {
        /// 仓库路径（设定自定义仓库）
        path: Option<String>,
        /// 切换到无仓库模式（保障本地模式）
        #[arg(long)]
        local: bool,
        /// 清除设定，恢复智能寻找
        #[arg(long)]
        auto: bool,
    },
    /// 查看运行日志（缺省列出全部日志）
    Log {
        /// 日志名: deploy/restore/snapshot/repo/ota/...
        name: Option<String>,
    },
}

#[derive(Subcommand)]
enum TrashCmd {
    /// 恢复某个批次到原位
    Restore {
        /// 批次标识: 编号/批次名/last
        target: String,
    },
    /// 永久清空回收站（不带参数清全部）
    Empty {
        /// 批次标识: 编号/批次名/last（可选）
        target: Option<String>,
    },
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
    // 恢复 SIGPIPE 默认处理：输出被管道截断（如 | head）时静默退出，不再 panic 刷屏
    unsafe {
        libc::signal(libc::SIGPIPE, libc::SIG_DFL);
    }
    let cli = Cli::parse();

    // Without subcommand: launch TUI if TTY, else help
    if cli.command.is_none() {
        if !atty::is(atty::Stream::Stdout) {
            print_help();
            return Ok(());
        }
        let cfg = AppConfig::discover()?;
        ui::run_tui(cfg)?;
        return Ok(());
    }

    // log 命令只读日志文件，不依赖仓库发现/校验，提前处理
    if let Some(Commands::Log { name }) = &cli.command {
        return core::log::log_cli(name.as_deref());
    }
    if let Some(Commands::Where { path, local, auto }) = &cli.command {
        return core::repo_loc::where_cli(path.as_deref(), *local, *auto);
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
                // 列宽按显示宽度（中文字符算 2 列），保证表头与内容对齐
                let pad = crate::core::utils::pad_display;
                println!(" {} {} {}", pad("编号", 4), pad("时间", 15), "备注");
                println!(" {} {} {}", "-".repeat(4), "-".repeat(15), "-".repeat(4));
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
                    let note = if p.join("manifest.txt").exists()
                        && !p.join(".bymgr-verified").exists()
                    {
                        format!("{} ⚠未校验", note)
                    } else {
                        note
                    };
                    println!(
                        " {} {} {}",
                        pad(&(i + 1).to_string(), 4),
                        pad(&p.file_name().unwrap().to_string_lossy(), 15),
                        note
                    );
                }
            }
        }
        Commands::Note { target, message } => {
            let name = core::snapshot::set_note(&cfg, &target, &message)?;
            println!("✅ {} 的备注已更新: {}", name, message);
        }
        Commands::Restore { target, force } => core::restore::restore_cli(&cfg, target, force)?,
        Commands::Verify { target } => core::snapshot::verify_cli(&cfg, target.as_deref())?,
        Commands::Diff { a, b } => core::snapshot::diff_cli(&cfg, &a, b.as_deref())?,
        Commands::Clean { keep, days } => core::clean::clean_cli(&cfg, keep, days)?,
        Commands::Deploy { mode, force } => {
            let mode = match mode {
                Some(m) => m,
                None => anyhow::bail!("用法: by-mgr deploy stow|local (必须明确指定模式)"),
            };
            let m = match mode.as_str() {
                "stow" => DeployMode::Stow,
                "local" => DeployMode::Local,
                _ => anyhow::bail!("未知部署模式: {} (可用 stow|local)", mode),
            };
            core::deploy::deploy_cli(&cfg, m, force)?;
        }
        Commands::Repo { cmd } => match cmd {
            None => anyhow::bail!("用法: by-mgr repo export|clean|replenish|edit (必须明确指定子命令)"),
            Some(RepoCmd::Export) => core::repo::repo_export(&cfg)?,
            Some(RepoCmd::Clean) => core::repo::repo_clean(&cfg)?,
            Some(RepoCmd::Replenish) => core::repo::repo_replenish(&cfg)?,
            Some(RepoCmd::Edit) => core::repo::repo_edit(&cfg)?,
        },
        Commands::Trash { cmd } => match cmd {
            None => core::trash::trash_list_cli(&cfg)?,
            Some(TrashCmd::Restore { target }) => core::trash::trash_restore_cli(&cfg, &target)?,
            Some(TrashCmd::Empty { target }) => {
                core::trash::trash_empty_cli(&cfg, target.as_deref())?
            }
        },
        Commands::Ota => core::ota::ota(&cfg)?,
        Commands::Log { .. } => unreachable!("log 已在仓库校验前处理"),
        Commands::Where { .. } => unreachable!("where 已在仓库校验前处理"),
    }
    Ok(())
}

fn print_help() {
    println!("用法: by-mgr [COMMAND]");
    println!();
    println!("命令:");
    println!("  snapshot [-m 备注]      创建快照");
    println!("  note <编号> <备注>       给快照设置/修改备注");
    println!("  list                  列出快照");
    println!("  restore [TARGET] [--force]  历史还原 (last/-1/编号/时间戳)");
    println!("  verify [TARGET]       校验快照完整性（缺省最新）");
    println!("  diff <A> [B]          对比两个快照的文件差异");
    println!("  clean -k <N> | -d <天数>  清理快照");
    println!("  deploy [stow|local]       部署配置");
    println!("  repo [export|clean|replenish|edit]  仓库管理");
    println!("  log [名称]            查看运行日志（缺省列出全部）");
    println!("  where [<路径>|--local|--auto]  仓库位置与模式");
    println!("  ota                   OTA 自更新");
    println!("  trash [restore|empty] 回收站（被删文件先到这里）");
    println!();
    println!("无参数时启动 TUI（非终端环境下打印此帮助）");
}
