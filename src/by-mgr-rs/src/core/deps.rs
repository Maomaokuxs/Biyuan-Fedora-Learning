use crate::config::AppConfig;
use anyhow::Result;
use std::process::Command;

struct PkgEntry {
    module: String,
    pkg: String,
    installed: bool,
}

fn rpm_installed(pkg: &str) -> bool {
    Command::new("rpm")
        .arg("-q")
        .arg(pkg)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// fc-list 输出的全部字体族名（小写归一化后比较）
fn font_families() -> Option<Vec<String>> {
    let out = Command::new("fc-list").arg(":").arg("family").output().ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let mut fams = Vec::new();
    // fc-list : family 每行就是逗号分隔的族名列表（无文件路径前缀）
    for line in text.lines() {
        for fam in line.split(',') {
            let f = fam.trim();
            if !f.is_empty() {
                fams.push(f.to_lowercase());
            }
        }
    }
    Some(fams)
}

fn service_running(name: &str) -> bool {
    // 进程名超过 15 字符会被内核截断，pgrep -x 匹配不到，改用 -f 匹配命令行
    let mut cmd = Command::new("pgrep");
    if name.chars().count() <= 15 {
        cmd.arg("-x");
    } else {
        cmd.arg("-f");
    }
    cmd.arg(name)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// 按显示宽度补空格到 w 列（中文 2 格、英文 1 格）
fn pad(s: &str, w: usize) -> String {
    let d: usize = s.chars().map(|c| if c.is_ascii() { 1 } else { 2 }).sum();
    if d >= w {
        s.to_string()
    } else {
        format!("{}{}", s, " ".repeat(w - d))
    }
}

pub fn deps_cli(cfg: &AppConfig, module: Option<&str>) -> Result<()> {
    let list_path = cfg.repo_dir.join("config/deps.list");
    let content = match std::fs::read_to_string(&list_path) {
        Ok(c) => c,
        Err(_) => {
            println!("未配置依赖清单（{} 不存在）", list_path.display());
            println!("在仓库 config/deps.list 中按“模块: 包 包”的格式添加后即可检查。");
            return Ok(());
        }
    };
    let mut pkgs: Vec<PkgEntry> = Vec::new();
    let mut fonts: Vec<String> = Vec::new();
    let mut services: Vec<String> = Vec::new();
    let mut seen_module = module.is_none();
    for (ln, raw) in content.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(name) = line.strip_prefix("font:") {
            fonts.push(name.trim().to_string());
            continue;
        }
        if let Some(name) = line.strip_prefix("service:") {
            services.push(name.trim().to_string());
            continue;
        }
        let Some((m, ps)) = line.split_once(':') else {
            eprintln!("第 {} 行格式不对（应为“模块: 包 包”），已跳过: {}", ln + 1, line);
            continue;
        };
        let m = m.trim();
        if let Some(want) = module {
            if want != m {
                continue;
            }
            seen_module = true;
        }
        for pkg in ps.split_whitespace() {
            pkgs.push(PkgEntry {
                module: m.to_string(),
                pkg: pkg.to_string(),
                installed: rpm_installed(pkg),
            });
        }
    }
    if let Some(want) = module {
        if !seen_module {
            println!("清单中没有模块 {}。", want);
            return Ok(());
        }
    }

    // 三表共用列宽：模块列取最长模块名，名称列取三类中最长项，状态列自然对齐
    let mod_w = pkgs.iter().map(|e| e.module.chars().count()).max().unwrap_or(0);
    let name_w = pkgs
        .iter()
        .map(|e| e.pkg.chars().count())
        .chain(fonts.iter().map(|f| f.chars().count()))
        .chain(services.iter().map(|x| x.chars().count()))
        .max()
        .unwrap_or(0);

    let mut missing_pkgs: Vec<String> = Vec::new();
    let mut missing_fonts: Vec<String> = Vec::new();
    let mut stopped: Vec<String> = Vec::new();

    if !pkgs.is_empty() {
        println!("软件包：");
        println!("  {} {} {}", pad("模块", mod_w), pad("包", name_w), "状态");
        let mut cur = String::new();
        for e in &pkgs {
            let m = if e.module != cur {
                if !cur.is_empty() {
                    println!();
                }
                cur = e.module.clone();
                e.module.clone()
            } else {
                String::new()
            };
            println!(
                "  {} {} {}",
                pad(&m, mod_w),
                pad(&e.pkg, name_w),
                if e.installed { "已安装" } else { "缺失" }
            );
            if !e.installed {
                missing_pkgs.push(e.pkg.clone());
            }
        }
    } else {
        println!("依赖清单中没有可检查的包。");
    }

    // 字体与服务是全局项，只在不指定模块时检查
    if module.is_none() {
        if !fonts.is_empty() {
            println!();
            println!("字体：");
            match font_families() {
                None => println!("  fontconfig 不可用，字体无法检查。"),
                Some(fams) => {
                    for f in &fonts {
                        let ok = fams.iter().any(|x| x == &f.to_lowercase());
                        println!("  {} {} {}", pad("", mod_w), pad(f, name_w), if ok { "已安装" } else { "缺失" });
                        if !ok {
                            missing_fonts.push(f.clone());
                        }
                    }
                }
            }
        }
        if !services.is_empty() {
            println!();
            println!("服务：");
            for s in &services {
                let ok = service_running(s);
                println!("  {} {} {}", pad("", mod_w), pad(s, name_w), if ok { "运行中" } else { "未运行" });
                if !ok {
                    stopped.push(s.clone());
                }
            }
        }
    }

    println!();
    let mut bad = false;
    if !missing_pkgs.is_empty() {
        println!("缺失 {} 个包: {}", missing_pkgs.len(), missing_pkgs.join(" "));
        println!("安装：sudo dnf install {}", missing_pkgs.join(" "));
        bad = true;
    }
    if !missing_fonts.is_empty() {
        println!("缺失 {} 个字体: {}", missing_fonts.len(), missing_fonts.join("、"));
        bad = true;
    }
    if !stopped.is_empty() {
        println!("未运行 {} 个服务: {}", stopped.len(), stopped.join(" "));
        bad = true;
    }
    if bad {
        std::process::exit(1);
    }
    // 指定模块时不检查字体/服务，汇总里按 0 计
    let checked_fonts = if module.is_none() { fonts.len() } else { 0 };
    let checked_services = if module.is_none() { services.len() } else { 0 };
    println!(
        "全部正常（包 {} 个、字体 {} 个、服务 {} 个）。",
        pkgs.len(),
        checked_fonts,
        checked_services
    );
    Ok(())
}
