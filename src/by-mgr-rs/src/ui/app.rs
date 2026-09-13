use anyhow::{anyhow, Result};
use crossterm::{
    event::{self, KeyCode, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{prelude::*, widgets::*};
use std::io;

use crate::config::AppConfig;
use crate::core::{self, DeployMode};
use crate::ui::theme;

#[derive(Debug, Clone, Copy, PartialEq)]
enum Page {
    Main,
    Backup,
    Deploy,
    System,
}

#[derive(Debug, Clone)]
struct MenuItem {
    title: &'static str,
    desc: &'static str,
}

pub fn run_tui(cfg: AppConfig) -> Result<()> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;
    terminal.hide_cursor().ok();

    let mut page = Page::Main;
    let mut selected: usize = 0;
    let mut status = String::from("q 退出  ↑↓/j k 移动  Enter 进入");

    loop {
        let count = match page {
            Page::Main => 3,
            Page::Backup => 3,
            Page::Deploy => 3,
            Page::System => 2,
        };
        if selected >= count {
            selected = count - 1;
        }

        terminal.draw(|f| {
            let area = f.area();
            // Outer block
            let title = match page {
                Page::Main => " by-mgr  — Biyuan 配置管理引擎 ",
                Page::Backup => " 备份与恢复 ",
                Page::Deploy => " 更新与部署 ",
                Page::System => " 系统配置 ",
            };
            let block = Block::default()
                .title(title)
                .borders(Borders::ALL)
                .border_type(BorderType::Rounded)
                .border_style(theme::border_style());
            f.render_widget(block, area);

            // Layout: header + body + footer
            let inner = Rect {
                x: area.x + 1,
                y: area.y + 1,
                width: area.width - 2,
                height: area.height - 2,
            };
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Min(5), Constraint::Length(1)])
                .split(inner);

            // Body: 3-column for Main, list for subs
            if page == Page::Main {
                let cols = Layout::default()
                    .direction(Direction::Horizontal)
                    .constraints([Constraint::Percentage(30), Constraint::Percentage(70)])
                    .split(chunks[0]);

                // Left nav
                let items = main_items();
                let list_items: Vec<ListItem> = items
                    .iter()
                    .enumerate()
                    .map(|(i, m)| {
                        let is_sel = i == selected;
                        let style = if is_sel { theme::selected_style() } else { theme::normal_style() };
                        let ind_style = if is_sel { theme::indicator_style() } else { theme::normal_style() };
                        ListItem::new(Line::from(vec![
                            Span::styled(if is_sel { "▶ " } else { "  " }, ind_style),
                            Span::styled(m.title, style),
                        ]))
                    })
                    .collect();
                let list = List::new(list_items)
                    .block(
                        Block::default()
                            .title(" 导航 ")
                            .borders(Borders::ALL)
                            .border_type(BorderType::Rounded),
                    )
                    .highlight_style(theme::selected_style());
                f.render_widget(list, cols[0]);

                // Right preview
                let preview = if selected < items.len() {
                    Paragraph::new(items[selected].desc)
                        .block(
                            Block::default()
                                .title(" 预览 ")
                                .borders(Borders::ALL)
                                .border_type(BorderType::Rounded),
                        )
                        .wrap(Wrap { trim: true })
                        .style(theme::normal_style())
                } else {
                    Paragraph::new("")
                };
                f.render_widget(preview, cols[1]);
            } else {
                let (items, title) = match page {
                    Page::Backup => (backup_items(), " 备份与恢复 "),
                    Page::Deploy => (deploy_items(), " 更新与部署 "),
                    Page::System => (system_items(), " 系统配置 "),
                    _ => (vec![], ""),
                };
                let list_items: Vec<ListItem> = items
                    .iter()
                    .enumerate()
                    .map(|(i, m)| {
                        let is_sel = i == selected;
                        let title_style = if is_sel { theme::selected_style() } else { theme::normal_style() };
                        let ind_style = if is_sel { theme::indicator_style() } else { theme::normal_style() };
                        let desc_style = if is_sel {
                            theme::muted_style().add_modifier(Modifier::DIM)
                        } else {
                            theme::muted_style()
                        };
                        ListItem::new(Line::from(vec![
                            Span::styled(if is_sel { "▶ " } else { "  " }, ind_style),
                            Span::styled(m.title, title_style),
                            Span::raw("  "),
                            Span::styled(m.desc, desc_style),
                        ]))
                    })
                    .collect();
                let list = List::new(list_items).block(
                    Block::default()
                        .title(title)
                        .borders(Borders::ALL)
                        .border_type(BorderType::Rounded),
                );
                f.render_widget(list, chunks[0]);
            }

            let footer = Paragraph::new(status.clone())
                .style(theme::normal_style())
                .alignment(Alignment::Center);
            f.render_widget(footer, chunks[1]);
        })?;

        if event::poll(std::time::Duration::from_millis(200))? {
            if let event::Event::Key(k) = event::read()? {
                match k.code {
                    KeyCode::Char('q') => {
                        if page == Page::Main {
                            break;
                        } else {
                            page = Page::Main;
                            selected = 0;
                        }
                    }
                    KeyCode::Esc => {
                        if page == Page::Main {
                            break;
                        } else {
                            page = Page::Main;
                            selected = 0;
                        }
                    }
                    KeyCode::Char('c') if k.modifiers.contains(KeyModifiers::CONTROL) => break,
                    KeyCode::Up | KeyCode::Char('k') => {
                        if selected > 0 {
                            selected -= 1;
                        }
                    }
                    KeyCode::Down | KeyCode::Char('j') => {
                        if selected + 1 < count {
                            selected += 1;
                        }
                    }
                    KeyCode::Enter => {
                        match page {
                            Page::Main => {
                                page = match selected {
                                    0 => Page::Backup,
                                    1 => Page::Deploy,
                                    2 => Page::System,
                                    _ => Page::Main,
                                };
                                selected = 0;
                            }
                            Page::Backup | Page::Deploy | Page::System => {
                                if page == Page::Backup && selected == 0 {
                                    status = "⏳ 正在创建快照...".to_string();
                                    terminal.draw(|f| {
                                        let area = f.area();
                                        let block = Block::default().title(" 备份与恢复 ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
                                        f.render_widget(block, area);
                                        let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                        let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                        let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                        f.render_widget(footer, chunks[1]);
                                    }).ok();
                                    let start = std::time::Instant::now();
                                    let res = execute_action(&cfg, page, selected);
                                    let elapsed = start.elapsed().as_millis();
                                    let log_dir = std::env::var("BY_MGR_LOG_DIR").unwrap_or_else(|_| "/tmp/by-mgr".to_string());
                                    let _ = std::fs::create_dir_all(&log_dir);
                                    let _ = std::fs::write(format!("{}/tui.log", log_dir), format!("{} | elapsed {}ms | {:?}\n", chrono::Local::now().format("%H:%M:%S"), elapsed, res));
                                    status = match res {
                                        Ok(msg) => format!("{} ({}ms)", msg, elapsed),
                                        Err(e) => format!("❌ {} ({}ms)", e, elapsed),
                                    };
                                    terminal.draw(|f| {
                                        let area = f.area();
                                        let block = Block::default().title(" 备份与恢复 ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
                                        f.render_widget(block, area);
                                        let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                        let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                        let items = backup_items();
                                        let list_items: Vec<ListItem> = items.iter().enumerate().map(|(i, m)| {
                                            let is_sel = i == selected;
                                            let title_style = if is_sel { theme::selected_style() } else { theme::normal_style() };
                                            let ind_style = if is_sel { theme::indicator_style() } else { theme::normal_style() };
                                            ListItem::new(Line::from(vec![Span::styled(if is_sel { "▶ " } else { "  " }, ind_style), Span::styled(m.title, title_style), Span::raw("  "), Span::styled(m.desc, theme::muted_style())]))
                                        }).collect();
                                        let list = List::new(list_items).block(Block::default().title(" 备份与恢复 ").borders(Borders::ALL).border_type(BorderType::Rounded));
                                        f.render_widget(list, chunks[0]);
                                        let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                        f.render_widget(footer, chunks[1]);
                                    }).ok();
                                } else if page == Page::Backup && selected == 1 {
                                    if let Some(tag) = tui_pick_snapshot(&mut terminal, &cfg) {
                                        status = format!("⏳ 正在还原 {}...", tag);
                                        terminal.draw(|f| {
                                            let area = f.area();
                                            let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                            let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                            f.render_widget(footer, chunks[1]);
                                        }).ok();
                                        let cnt = core::restore::restore_cli_quiet(&cfg, tag.clone()).unwrap_or_else(|_| "0".to_string());
                                        let res: Result<(), anyhow::Error> = if cnt == "0" { Err(anyhow!("无模块")) } else { Ok(()) };
                                        status = match res {
                                            Ok(_) => format!("✅ 已还原 {} ({} 模块)", tag, cnt),
                                            Err(e) => format!("❌ 还原失败: {}", e),
                                        };
                                        terminal.draw(|f| {
                                            let area = f.area();
                                            let block = Block::default().title(" 备份与恢复 ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
                                            f.render_widget(block, area);
                                            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                            let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                            let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                            f.render_widget(footer, chunks[1]);
                                        }).ok();
                                    } else {
                                        status = "已取消".to_string();
                                    }
                                } else if page == Page::Backup && selected == 2 {
                                    let count = std::fs::read_dir(&cfg.backup_root)
                                        .map(|it| it.flatten().filter(|e| e.path().is_dir())
                                            .filter(|e| e.file_name().to_string_lossy().contains('_')).count())
                                        .unwrap_or(0);
                                    if let Some(mode) = tui_pick_clean_mode(&mut terminal, count) {
                                        let prompt = if mode == 0 {
                                            format!("保留最近 N 个 (当前共 {} 个)", count)
                                        } else {
                                            "删除 N 天前".to_string()
                                        };
                                        if let Some(num_str) = tui_input_number(&mut terminal, &prompt) {
                                            let n: usize = num_str.parse().unwrap_or(0);
                                            status = "⏳ 正在清理...".to_string();
                                            terminal.draw(|f| {
                                                let area = f.area();
                                                let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                                let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                                let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                                f.render_widget(footer, chunks[1]);
                                            }).ok();
                                            let res = if mode == 0 {
                                                core::clean::clean_cli_quiet(&cfg, Some(n), None)
                                            } else {
                                                core::clean::clean_cli_quiet(&cfg, None, Some(n as u64))
                                            };
                                            status = match res {
                                                Ok(msg) => msg,
                                                Err(e) => format!("❌ {}", e),
                                            };
                                        } else {
                                            status = "已取消".to_string();
                                        }
                                    } else {
                                        status = "已取消".to_string();
                                    }
                                    terminal.draw(|f| {
                                        let area = f.area();
                                        let block = Block::default().title(" 备份与恢复 ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
                                        f.render_widget(block, area);
                                        let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                        let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                        let items = backup_items();
                                        let list_items: Vec<ListItem> = items.iter().enumerate().map(|(i, m)| {
                                            let is_sel = i == selected;
                                            let title_style = if is_sel { theme::selected_style() } else { theme::normal_style() };
                                            let ind_style = if is_sel { theme::indicator_style() } else { theme::normal_style() };
                                            ListItem::new(Line::from(vec![Span::styled(if is_sel { "▶ " } else { "  " }, ind_style), Span::styled(m.title, title_style), Span::raw("  "), Span::styled(m.desc, theme::muted_style())]))
                                        }).collect();
                                        let list = List::new(list_items).block(Block::default().title(" 备份与恢复 ").borders(Borders::ALL).border_type(BorderType::Rounded));
                                        f.render_widget(list, chunks[0]);
                                        let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                        f.render_widget(footer, chunks[1]);
                                    }).ok();
                                } else if page == Page::Deploy {
                                    if selected == 2 {
                                        // OTA 自更新：不离屏，底栏展示
                                        status = "⏳ 正在检查 OTA...".to_string();
                                        terminal.draw(|f| {
                                            let area = f.area();
                                            let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                            let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                            f.render_widget(footer, chunks[1]);
                                        }).ok();
                                        let res = core::ota::ota_quiet(&cfg);
                                        status = match res {
                                            Ok(msg) => msg,
                                            Err(e) => format!("❌ {}", e),
                                        };
                                        terminal.draw(|f| {
                                            let area = f.area();
                                            let block = Block::default().title(" 更新与部署 ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
                                            f.render_widget(block, area);
                                            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                            let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                            let items = deploy_items();
                                            let list_items: Vec<ListItem> = items.iter().enumerate().map(|(i, m)| {
                                                let is_sel = i == selected;
                                                let title_style = if is_sel { theme::selected_style() } else { theme::normal_style() };
                                                let ind_style = if is_sel { theme::indicator_style() } else { theme::normal_style() };
                                                ListItem::new(Line::from(vec![Span::styled(if is_sel { "▶ " } else { "  " }, ind_style), Span::styled(m.title, title_style), Span::raw("  "), Span::styled(m.desc, theme::muted_style())]))
                                            }).collect();
                                            let list = List::new(list_items).block(Block::default().title(" 更新与部署 ").borders(Borders::ALL).border_type(BorderType::Rounded));
                                            f.render_widget(list, chunks[0]);
                                            let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                            f.render_widget(footer, chunks[1]);
                                        }).ok();
                                    } else {
                                        let mode = if selected == 0 { DeployMode::Stow } else { DeployMode::Local };
                                        // 本地部署：遇同名文件先询问是否快照
                                        if mode == DeployMode::Local {
                                            let has_conflict = cfg.dotfiles_modules().iter().any(|m| {
                                                let p = crate::config::get_target_path(&dirs::home_dir().unwrap(), m);
                                                p.exists() || p.is_symlink()
                                            });
                                            if has_conflict {
                                                if let Some(do_snap) = tui_confirm_snapshot(&mut terminal) {
                                                    if do_snap {
                                                        status = "⏳ 正在创建快照...".to_string();
                                                        terminal.draw(|f| {
                                                            let area = f.area();
                                                            let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                                            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                                            let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                                            f.render_widget(footer, chunks[1]);
                                                        }).ok();
                                                        match core::snapshot::snapshot(&cfg) {
                                                            Ok(msg) => status = format!("{} | 继续部署...", msg),
                                                            Err(e) => status = format!("❌ 快照失败: {} | 继续部署", e),
                                                        }
                                                        terminal.draw(|f| {
                                                            let area = f.area();
                                                            let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                                            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                                            let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                                            f.render_widget(footer, chunks[1]);
                                                        }).ok();
                                                        std::thread::sleep(std::time::Duration::from_millis(800));
                                                    }
                                                } else {
                                                    status = "已取消".to_string();
                                                    terminal.draw(|f| {
                                                        let area = f.area();
                                                        let block = Block::default().title(" 更新与部署 ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
                                                        f.render_widget(block, area);
                                                        let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                                        let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                                        let items = deploy_items();
                                                        let list_items: Vec<ListItem> = items.iter().enumerate().map(|(i, m)| {
                                                            let is_sel = i == selected;
                                                            let title_style = if is_sel { theme::selected_style() } else { theme::normal_style() };
                                                            let ind_style = if is_sel { theme::indicator_style() } else { theme::normal_style() };
                                                            ListItem::new(Line::from(vec![Span::styled(if is_sel { "▶ " } else { "  " }, ind_style), Span::styled(m.title, title_style), Span::raw("  "), Span::styled(m.desc, theme::muted_style())]))
                                                        }).collect();
                                                        let list = List::new(list_items).block(Block::default().title(" 更新与部署 ").borders(Borders::ALL).border_type(BorderType::Rounded));
                                                        f.render_widget(list, chunks[0]);
                                                        let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                                        f.render_widget(footer, chunks[1]);
                                                    }).ok();
                                                    continue;
                                                }
                                            }
                                        }
                                        status = "⏳ 正在部署...".to_string();
                                        terminal.draw(|f| {
                                            let area = f.area();
                                            let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                            let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                            f.render_widget(footer, chunks[1]);
                                        }).ok();
                                        let res = core::deploy::deploy_cli_quiet(&cfg, mode);
                                        status = match res {
                                            Ok(msg) => msg,
                                            Err(e) => format!("❌ {}", e),
                                        };
                                        terminal.draw(|f| {
                                            let area = f.area();
                                            let block = Block::default().title(" 更新与部署 ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
                                            f.render_widget(block, area);
                                            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                            let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                            let items = deploy_items();
                                            let list_items: Vec<ListItem> = items.iter().enumerate().map(|(i, m)| {
                                                let is_sel = i == selected;
                                                let title_style = if is_sel { theme::selected_style() } else { theme::normal_style() };
                                                let ind_style = if is_sel { theme::indicator_style() } else { theme::normal_style() };
                                                ListItem::new(Line::from(vec![Span::styled(if is_sel { "▶ " } else { "  " }, ind_style), Span::styled(m.title, title_style), Span::raw("  "), Span::styled(m.desc, theme::muted_style())]))
                                            }).collect();
                                            let list = List::new(list_items).block(Block::default().title(" 更新与部署 ").borders(Borders::ALL).border_type(BorderType::Rounded));
                                            f.render_widget(list, chunks[0]);
                                            let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                            f.render_widget(footer, chunks[1]);
                                        }).ok();
                                    }
                                } else if page == Page::System {
                                    if selected == 0 {
                                        if let Some(choice) = tui_pick_repo(&mut terminal) {
                                            if choice == 1 {
                                                // 清理失效仓库：图形进度条 + sudo 可视化，避免“卡住”
                                                let sudo_msg = "⏳ 正在请求 sudo 授权...";
                                                terminal.draw(|f| {
                                                    let area = f.area();
                                                    let block = Block::default().title(" 清理失效仓库 ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
                                                    f.render_widget(block, area);
                                                    let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                                    let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Length(3), Constraint::Min(1), Constraint::Length(1)]).split(inner);
                                                    let gauge = Gauge::default().block(Block::default().title(" 进度 ").borders(Borders::ALL).border_type(BorderType::Rounded)).gauge_style(theme::selected_style()).percent(0).label("0%");
                                                    f.render_widget(gauge, chunks[0]);
                                                    let info = Paragraph::new(sudo_msg).style(theme::muted_style()).alignment(Alignment::Center);
                                                    f.render_widget(info, chunks[1]);
                                                    let footer = Paragraph::new("请输入 sudo 密码后回车（如已授权则直接继续）").style(theme::normal_style()).alignment(Alignment::Center);
                                                    f.render_widget(footer, chunks[2]);
                                                }).ok();
                                                // 确保 sudo 已授权，离屏 raw 以显示密码提示
                                                disable_raw_mode().ok();
                                                let _ = std::process::Command::new("sudo").arg("-v").status();
                                                enable_raw_mode().ok();
                                                terminal.hide_cursor().ok();
                                                let (tx, rx) = std::sync::mpsc::channel();
                                                let cfg_clone = cfg.clone();
                                                std::thread::spawn(move || {
                                                    let res = core::repo::repo_clean_progress(&cfg_clone, |cur, total, id| {
                                                        let _ = tx.send((cur, total, id.to_string()));
                                                    });
                                                    let _ = tx.send((100, 100, res.unwrap_or_else(|e| format!("❌ {}", e))));
                                                });
                                                let mut cur = 0; let mut total = 1; let mut last_id = String::new();
                                                while let Ok((c, t, id)) = rx.recv() {
                                                    cur = c; total = t; last_id = id.clone();
                                                    let is_final = last_id.starts_with("✅") || last_id.starts_with("❌");
                                                    let pct = if total == 0 { 100 } else { (cur * 100 / total).min(100) as u16 };
                                                    let label = if is_final { last_id.clone() } else { format!("{}/{} {}", cur, total, last_id) };
                                                    terminal.draw(|f| {
                                                        let area = f.area();
                                                        let block = Block::default().title(" 清理失效仓库 ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
                                                        f.render_widget(block, area);
                                                        let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                                        let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Length(3), Constraint::Min(1), Constraint::Length(1)]).split(inner);
                                                        let gauge = Gauge::default().block(Block::default().title(" 进度 ").borders(Borders::ALL).border_type(BorderType::Rounded)).gauge_style(theme::selected_style()).percent(pct).label(label.clone());
                                                        f.render_widget(gauge, chunks[0]);
                                                        let info = if is_final {
                                                            Paragraph::new(last_id.clone()).style(theme::selected_style()).alignment(Alignment::Center)
                                                        } else {
                                                            Paragraph::new(format!("正在检查: {}", last_id)).style(theme::muted_style()).alignment(Alignment::Center)
                                                        };
                                                        f.render_widget(info, chunks[1]);
                                                        let footer = if is_final {
                                                            Paragraph::new(last_id.clone()).style(theme::normal_style()).alignment(Alignment::Center)
                                                        } else {
                                                            Paragraph::new("请稍候，正在逐个校验仓库...").style(theme::normal_style()).alignment(Alignment::Center)
                                                        };
                                                        f.render_widget(footer, chunks[2]);
                                                    }).ok();
                                                    if is_final {
                                                        status = last_id.clone();
                                                        break;
                                                    }
                                                }
                                                if !last_id.starts_with("✅") && !last_id.starts_with("❌") {
                                                    status = format!("✅ 清理完成 {}/{}", cur, total);
                                                } else {
                                                    status = last_id;
                                                }
                                            } else {
                                                status = "⏳ 正在处理仓库...".to_string();
                                                terminal.draw(|f| {
                                                    let area = f.area();
                                                    let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                                    let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                                    let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                                    f.render_widget(footer, chunks[1]);
                                                }).ok();
                                                let res = match choice {
                                                    0 => core::repo::repo_export_quiet(&cfg),
                                                    2 => core::repo::repo_replenish_quiet(&cfg),
                                                    _ => Ok("已取消".to_string()),
                                                };
                                                status = match res {
                                                    Ok(msg) => msg,
                                                    Err(e) => format!("❌ {}", e),
                                                };
                                            }
                                        } else {
                                            status = "已取消".to_string();
                                        }
                                        terminal.draw(|f| {
                                            let area = f.area();
                                            let block = Block::default().title(" 系统配置 ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
                                            f.render_widget(block, area);
                                            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                            let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                            let items = system_items();
                                            let list_items: Vec<ListItem> = items.iter().enumerate().map(|(i, m)| {
                                                let is_sel = i == selected;
                                                let title_style = if is_sel { theme::selected_style() } else { theme::normal_style() };
                                                let ind_style = if is_sel { theme::indicator_style() } else { theme::normal_style() };
                                                ListItem::new(Line::from(vec![Span::styled(if is_sel { "▶ " } else { "  " }, ind_style), Span::styled(m.title, title_style), Span::raw("  "), Span::styled(m.desc, theme::muted_style())]))
                                            }).collect();
                                            let list = List::new(list_items).block(Block::default().title(" 系统配置 ").borders(Borders::ALL).border_type(BorderType::Rounded));
                                            f.render_widget(list, chunks[0]);
                                            let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                            f.render_widget(footer, chunks[1]);
                                        }).ok();
                                    } else if selected == 1 {
                                        if let Some(ed) = tui_pick_editor(&mut terminal) {
                                            status = "⏳ 正在设置编辑器...".to_string();
                                            terminal.draw(|f| {
                                                let area = f.area();
                                                let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                                let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                                let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                                f.render_widget(footer, chunks[1]);
                                            }).ok();
                                            let res = core::editor::editor_quiet(&cfg, &ed);
                                            status = match res {
                                                Ok(msg) => msg,
                                                Err(e) => format!("❌ {}", e),
                                            };
                                        } else {
                                            status = "已取消".to_string();
                                        }
                                        terminal.draw(|f| {
                                            let area = f.area();
                                            let block = Block::default().title(" 系统配置 ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
                                            f.render_widget(block, area);
                                            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
                                            let chunks = Layout::default().direction(Direction::Vertical).constraints([Constraint::Min(5), Constraint::Length(1)]).split(inner);
                                            let items = system_items();
                                            let list_items: Vec<ListItem> = items.iter().enumerate().map(|(i, m)| {
                                                let is_sel = i == selected;
                                                let title_style = if is_sel { theme::selected_style() } else { theme::normal_style() };
                                                let ind_style = if is_sel { theme::indicator_style() } else { theme::normal_style() };
                                                ListItem::new(Line::from(vec![Span::styled(if is_sel { "▶ " } else { "  " }, ind_style), Span::styled(m.title, title_style), Span::raw("  "), Span::styled(m.desc, theme::muted_style())]))
                                            }).collect();
                                            let list = List::new(list_items).block(Block::default().title(" 系统配置 ").borders(Borders::ALL).border_type(BorderType::Rounded));
                                            f.render_widget(list, chunks[0]);
                                            let footer = Paragraph::new(status.clone()).style(theme::normal_style()).alignment(Alignment::Center);
                                            f.render_widget(footer, chunks[1]);
                                        }).ok();
                                    } else {
                                        status = "已取消".to_string();
                                    }
                                } else {
                                    // 其他需交互的功能仍离开 TUI
                                    disable_raw_mode().ok();
                                    execute!(terminal.backend_mut(), LeaveAlternateScreen).ok();
                                    terminal.show_cursor().ok();
                                    let res = execute_action(&cfg, page, selected);
                                    status = match res {
                                        Ok(msg) => msg,
                                        Err(e) => format!("❌ {}", e),
                                    };
                                    println!("\n按回车继续...");
                                    let mut s = String::new();
                                    let _ = io::stdin().read_line(&mut s);
                                    enable_raw_mode().ok();
                                    execute!(terminal.backend_mut(), EnterAlternateScreen).ok();
                                    terminal.hide_cursor().ok();
                                }
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
    }

    terminal.show_cursor().ok();
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    Ok(())
}

fn tui_pick_snapshot<W: Backend>(terminal: &mut Terminal<W>, cfg: &AppConfig) -> Option<String> where W: ratatui::backend::Backend {
    let mut list: Vec<String> = std::fs::read_dir(&cfg.backup_root).ok()?.flatten()
        .filter(|e| e.path().is_dir())
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|n| n.contains('_') && n.len() >= 15)
        .collect();
    if list.is_empty() { return None; }
    list.sort(); list.reverse();
    let mut sel = 0usize;
    loop {
        terminal.draw(|f| {
            let area = f.area();
            let block = Block::default().title(" 选择历史快照 (Enter 确认, Esc 取消) ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
            f.render_widget(block, area);
            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
            let items: Vec<ListItem> = list.iter().enumerate().map(|(i, n)| {
                let style = if i == sel { theme::selected_style() } else { theme::normal_style() };
                let ind = if i == sel { theme::indicator_style() } else { theme::normal_style() };
                ListItem::new(Line::from(vec![Span::styled(if i==sel {"▶ "} else {"  "}, ind), Span::styled(n.clone(), style)]))
            }).collect();
            let list_w = List::new(items).block(Block::default().title(" 快照 ").borders(Borders::ALL).border_type(BorderType::Rounded));
            f.render_widget(list_w, inner);
        }).ok()?;
        if event::poll(std::time::Duration::from_millis(200)).ok()? {
            if let event::Event::Key(k) = event::read().ok()? {
                match k.code {
                    KeyCode::Esc | KeyCode::Char('q') => return None,
                    KeyCode::Up | KeyCode::Char('k') => if sel > 0 { sel -= 1 },
                    KeyCode::Down | KeyCode::Char('j') => if sel + 1 < list.len() { sel += 1 },
                    KeyCode::Enter => return Some(list[sel].clone()),
                    _ => {}
                }
            }
        }
    }
}

fn tui_pick_clean_mode<W: Backend>(terminal: &mut Terminal<W>, count: usize) -> Option<usize> where W: ratatui::backend::Backend {
    let opts = vec!["按数量 保留最近 N 个", "按日期 删除 N 天前"];
    let mut sel = 0usize;
    loop {
        terminal.draw(|f| {
            let area = f.area();
            let block = Block::default().title(format!(" 清理模式 (当前共 {} 个 | Enter 确认, Esc 取消) ", count)).borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
            f.render_widget(block, area);
            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
            let items: Vec<ListItem> = opts.iter().enumerate().map(|(i, o)| {
                let style = if i == sel { theme::selected_style() } else { theme::normal_style() };
                let ind = if i == sel { theme::indicator_style() } else { theme::normal_style() };
                // 按数量模式额外显示总数
                let label = if *o == "按数量 保留最近 N 个" {
                    format!("{} (共 {} 个)", o, count)
                } else { o.to_string() };
                ListItem::new(Line::from(vec![Span::styled(if i==sel {"▶ "} else {"  "}, ind), Span::styled(label, style)]))
            }).collect();
            let list_w = List::new(items).block(Block::default().title(" 模式 ").borders(Borders::ALL).border_type(BorderType::Rounded));
            f.render_widget(list_w, inner);
        }).ok()?;
        if event::poll(std::time::Duration::from_millis(200)).ok()? {
            if let event::Event::Key(k) = event::read().ok()? {
                match k.code {
                    KeyCode::Esc | KeyCode::Char('q') => return None,
                    KeyCode::Up | KeyCode::Char('k') => if sel > 0 { sel -= 1 },
                    KeyCode::Down | KeyCode::Char('j') => if sel + 1 < opts.len() { sel += 1 },
                    KeyCode::Enter => return Some(sel),
                    _ => {}
                }
            }
        }
    }
}

fn tui_input_number<W: Backend>(terminal: &mut Terminal<W>, prompt: &str) -> Option<String> where W: ratatui::backend::Backend {
    let mut input = String::new();
    loop {
        terminal.draw(|f| {
            let area = f.area();
            let block = Block::default().title(format!(" {} (Enter 确认, Esc 取消) ", prompt)).borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
            f.render_widget(block, area);
            let inner = Rect { x: area.x+2, y: area.y+2, width: area.width-4, height: 3 };
            let para = Paragraph::new(input.clone()).block(Block::default().borders(Borders::ALL).border_type(BorderType::Rounded).title(" 输入数字 ")).style(theme::normal_style());
            f.render_widget(para, inner);
            let footer = Paragraph::new("输入数字后 Enter 确认").style(theme::muted_style()).alignment(Alignment::Center);
            let foot_area = Rect { x: area.x+1, y: area.height-2, width: area.width-2, height: 1 };
            f.render_widget(footer, foot_area);
        }).ok()?;
        if event::poll(std::time::Duration::from_millis(200)).ok()? {
            if let event::Event::Key(k) = event::read().ok()? {
                match k.code {
                    KeyCode::Esc => return None,
                    KeyCode::Enter => if !input.is_empty() && input.parse::<usize>().is_ok() { return Some(input); },
                    KeyCode::Backspace => { input.pop(); },
                    KeyCode::Char(c) if c.is_ascii_digit() => input.push(c),
                    _ => {}
                }
            }
        }
    }
}

fn tui_confirm_snapshot<W: Backend>(terminal: &mut Terminal<W>) -> Option<bool> where W: ratatui::backend::Backend {
    let opts = vec!["是 (先创建快照)", "否 (直接覆盖)", "取消"];
    let mut sel = 1usize; // 默认否
    loop {
        terminal.draw(|f| {
            let area = f.area();
            let block = Block::default().title(" 检测到同名文件，是否先创建快照？ (Enter 确认, Esc 取消) ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
            f.render_widget(block, area);
            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
            let items: Vec<ListItem> = opts.iter().enumerate().map(|(i, o)| {
                let style = if i == sel { theme::selected_style() } else { theme::normal_style() };
                let ind = if i == sel { theme::indicator_style() } else { theme::normal_style() };
                ListItem::new(Line::from(vec![Span::styled(if i==sel {"▶ "} else {"  "}, ind), Span::styled(*o, style)]))
            }).collect();
            let list_w = List::new(items).block(Block::default().title(" 确认 ").borders(Borders::ALL).border_type(BorderType::Rounded));
            f.render_widget(list_w, inner);
        }).ok()?;
        if event::poll(std::time::Duration::from_millis(200)).ok()? {
            if let event::Event::Key(k) = event::read().ok()? {
                match k.code {
                    KeyCode::Esc | KeyCode::Char('q') => return None,
                    KeyCode::Up | KeyCode::Char('k') => if sel > 0 { sel -= 1 },
                    KeyCode::Down | KeyCode::Char('j') => if sel + 1 < opts.len() { sel += 1 },
                    KeyCode::Enter => match sel {
                        0 => return Some(true),
                        1 => return Some(false),
                        _ => return None,
                    },
                    _ => {}
                }
            }
        }
    }
}

fn tui_pick_repo<W: Backend>(terminal: &mut Terminal<W>) -> Option<usize> where W: ratatui::backend::Backend {
    let opts = vec!["导出清单", "清理失效仓库", "增量补齐", "编辑清单"];
    let mut sel = 0usize;
    loop {
        terminal.draw(|f| {
            let area = f.area();
            let block = Block::default().title(" 仓库管理 (Enter 确认, Esc 取消) ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
            f.render_widget(block, area);
            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
            let items: Vec<ListItem> = opts.iter().enumerate().map(|(i, o)| {
                let style = if i == sel { theme::selected_style() } else { theme::normal_style() };
                let ind = if i == sel { theme::indicator_style() } else { theme::normal_style() };
                ListItem::new(Line::from(vec![Span::styled(if i==sel {"▶ "} else {"  "}, ind), Span::styled(*o, style)]))
            }).collect();
            let list_w = List::new(items).block(Block::default().title(" 操作 ").borders(Borders::ALL).border_type(BorderType::Rounded));
            f.render_widget(list_w, inner);
        }).ok()?;
        if event::poll(std::time::Duration::from_millis(200)).ok()? {
            if let event::Event::Key(k) = event::read().ok()? {
                match k.code {
                    KeyCode::Esc | KeyCode::Char('q') => return None,
                    KeyCode::Up | KeyCode::Char('k') => if sel > 0 { sel -= 1 },
                    KeyCode::Down | KeyCode::Char('j') => if sel + 1 < opts.len() { sel += 1 },
                    KeyCode::Enter => return Some(sel),
                    _ => {}
                }
            }
        }
    }
}

fn tui_pick_editor<W: Backend>(terminal: &mut Terminal<W>) -> Option<String> where W: ratatui::backend::Backend {
    let editors = vec!["nvim", "vim", "nano", "kate"];
    // 检测当前系统默认编辑器
    let current = std::process::Command::new("bash")
        .arg("-c")
        .arg("readlink -f /etc/alternatives/editor 2>/dev/null | xargs basename; echo $EDITOR; git config --global core.editor 2>/dev/null | head -1")
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
        .unwrap_or_default();
    let mut sel = editors.iter().position(|e| current.lines().any(|l| l.trim() == *e)).unwrap_or(0);
    loop {
        terminal.draw(|f| {
            let area = f.area();
            let block = Block::default().title(" 选择编辑器 (✓当前 前景已装 背景未装 Enter 确认, Esc 取消) ").borders(Borders::ALL).border_type(BorderType::Rounded).border_style(theme::border_style());
            f.render_widget(block, area);
            let inner = Rect { x: area.x+1, y: area.y+1, width: area.width-2, height: area.height-2 };
            let items: Vec<ListItem> = editors.iter().enumerate().map(|(i, e)| {
                let installed = std::process::Command::new("bash").arg("-c").arg(format!("command -v {} >/dev/null 2>&1", e)).status().map(|s| s.success()).unwrap_or(false);
                let is_current = current.lines().any(|l| l.trim() == *e);
                let mark = if is_current { "✓" } else { " " };
                let base_style = if !installed { theme::muted_style() } else { theme::normal_style() };
                let style = if i == sel { theme::selected_style() } else { base_style };
                let ind = if i == sel { theme::indicator_style() } else { theme::normal_style() };
                ListItem::new(Line::from(vec![Span::styled(if i==sel {"▶ "} else {"  "}, ind), Span::styled(format!("[{}] {}", mark, e), style)]))
            }).collect();
            let list_w = List::new(items).block(Block::default().title(" 编辑器 ").borders(Borders::ALL).border_type(BorderType::Rounded));
            f.render_widget(list_w, inner);
        }).ok()?;
        if event::poll(std::time::Duration::from_millis(200)).ok()? {
            if let event::Event::Key(k) = event::read().ok()? {
                match k.code {
                    KeyCode::Esc | KeyCode::Char('q') => return None,
                    KeyCode::Up | KeyCode::Char('k') => if sel > 0 { sel -= 1 },
                    KeyCode::Down | KeyCode::Char('j') => if sel + 1 < editors.len() { sel += 1 },
                    KeyCode::Enter => return Some(editors[sel].to_string()),
                    _ => {}
                }
            }
        }
    }
}

fn main_items() -> Vec<MenuItem> {
    vec![
        MenuItem { title: "备份与恢复", desc: "快照创建 · 历史还原(本地/Stow) · 清理\n快照路径: ~/.config/by-mgr/backup/YYYYMMDD_HHMMSS" },
        MenuItem { title: "更新与部署", desc: "Stow 链接部署 · 本地复制部署 · OTA 自更新\n含 starship/mako 模板同步与 theme-sync 触发" },
        MenuItem { title: "系统配置", desc: "仓库管理(导出/清理/补齐/编辑) · 编辑器设置\n（已移除: NVIDIA/DM/Plymouth/休眠）" },
    ]
}
fn backup_items() -> Vec<MenuItem> {
    vec![
        MenuItem { title: "创建快照", desc: "备份当前系统配置到 ~/.config/by-mgr/backup/" },
        MenuItem { title: "历史还原", desc: "选择历史备份点，按模块还原（本地/Stow）" },
        MenuItem { title: "清理快照", desc: "按数量或日期删除旧备份" },
    ]
}
fn deploy_items() -> Vec<MenuItem> {
    vec![
        MenuItem { title: "Stow 部署", desc: "软链接方式部署（推荐）" },
        MenuItem { title: "本地部署", desc: "直接复制配置文件到系统目录" },
        MenuItem { title: "OTA 自更新", desc: "从 GitHub 拉取最新版 by-mgr" },
    ]
}
fn system_items() -> Vec<MenuItem> {
    vec![
        MenuItem { title: "仓库管理", desc: "导出清单 · 清理失效仓库 · 增量补齐 · 编辑清单" },
        MenuItem { title: "编辑器设置", desc: "设置系统默认编辑器 (nvim/vim/nano/kate)" },
    ]
}

fn execute_action(cfg: &AppConfig, page: Page, idx: usize) -> Result<String> {
    match (page, idx) {
        (Page::Backup, 0) => {
            let tag = core::snapshot::snapshot(cfg)?;
            Ok(format!("✅ 快照已创建: {}", tag))
        }
        (Page::Backup, 1) => {
            core::restore::restore_interactive(cfg)?;
            Ok("✅ 历史还原完成".to_string())
        }
        (Page::Backup, 2) => {
            core::clean::clean_interactive(cfg)?;
            Ok("✅ 清理完成".to_string())
        }
        (Page::Deploy, 0) => {
            core::deploy::deploy_cli(cfg, DeployMode::Stow)?;
            Ok("✅ Stow 部署完成".to_string())
        }
        (Page::Deploy, 1) => {
            core::deploy::deploy_cli(cfg, DeployMode::Local)?;
            Ok("✅ 本地部署完成".to_string())
        }
        (Page::Deploy, 2) => {
            core::ota::ota(cfg)?;
            Ok("✨ OTA 更新成功".to_string())
        }
        (Page::System, 0) => {
            core::repo::repo_manager(cfg)?;
            Ok("✅ 仓库管理完成".to_string())
        }
        (Page::System, 1) => {
            core::editor::editor_settings(cfg)?;
            Ok("✅ 编辑器设置完成".to_string())
        }
        _ => Ok("未实现".to_string()),
    }
}
