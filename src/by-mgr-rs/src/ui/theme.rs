use ratatui::style::{Color, Style, Modifier};

// Fallback Catppuccin Mocha
const FALLBACK_FG: Color = Color::Rgb(205, 214, 244);
const FALLBACK_BG: Color = Color::Rgb(30, 30, 46);
const FALLBACK_ACCENT: Color = Color::Rgb(203, 166, 247);
const FALLBACK_MUTED: Color = Color::Rgb(108, 112, 134);

#[derive(Debug, Clone)]
struct Palette {
    bg: Color,
    fg: Color,
    accent: Color,
    muted: Color,
}

fn hex_to_color(s: &str) -> Option<Color> {
    let h = s.trim().trim_matches('"').trim_matches('\'').trim_start_matches('#');
    if h.len() != 6 { return None; }
    let r = u8::from_str_radix(&h[0..2], 16).ok()?;
    let g = u8::from_str_radix(&h[2..4], 16).ok()?;
    let b = u8::from_str_radix(&h[4..6], 16).ok()?;
    Some(Color::Rgb(r, g, b))
}

fn load_palette() -> Palette {
    let path = dirs::home_dir()
        .map(|h| h.join(".cache/by-mgr/hellwal/global-palette.env"))
        .unwrap_or_default();
    let mut bg = None;
    let mut fg = None;
    let mut accent = None;
    let mut muted = None;
    if let Ok(content) = std::fs::read_to_string(&path) {
        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') { continue; }
            if let Some(v) = line.strip_prefix("BG=") { bg = hex_to_color(v); }
            else if let Some(v) = line.strip_prefix("FG=") { fg = hex_to_color(v); }
            else if let Some(v) = line.strip_prefix("ACCENT=") { accent = hex_to_color(v); }
            else if let Some(v) = line.strip_prefix("MUTED=") { muted = hex_to_color(v); }
        }
    }
    Palette {
        bg: bg.unwrap_or(FALLBACK_BG),
        fg: fg.unwrap_or(FALLBACK_FG),
        accent: accent.unwrap_or(FALLBACK_ACCENT),
        muted: muted.unwrap_or(FALLBACK_MUTED),
    }
}

// 动态获取：每次调用都重新读取文件，确保壁纸切换后立即生效
fn palette() -> Palette {
    load_palette()
}

pub fn fg() -> Color { palette().fg }
pub fn bg() -> Color { palette().bg }
pub fn accent() -> Color { palette().accent }
pub fn muted() -> Color { palette().muted }

pub const FG: Color = FALLBACK_FG;
pub const BG: Color = FALLBACK_BG;
pub const MAUVE: Color = FALLBACK_ACCENT;
pub const BLUE: Color = Color::Rgb(137, 180, 250);
pub const GREEN: Color = Color::Rgb(166, 227, 161);
pub const RED: Color = Color::Rgb(243, 139, 168);
pub const YELLOW: Color = Color::Rgb(249, 226, 175);
pub const PEACH: Color = Color::Rgb(250, 179, 135);

pub fn selected_style() -> Style {
    let p = palette();
    // 选中：与 ▶ 同色 ACCENT + 粗体下划线，未选中保持 FG
    Style::default().fg(p.accent).add_modifier(Modifier::BOLD | Modifier::UNDERLINED)
}
pub fn indicator_style() -> Style {
    // 指示符 ▶ 使用 ACCENT 区分标题
    Style::default().fg(palette().accent).add_modifier(Modifier::BOLD)
}
pub fn normal_style() -> Style {
    Style::default().fg(palette().fg)
}
pub fn border_style() -> Style {
    Style::default().fg(palette().accent)
}
pub fn header_style() -> Style {
    Style::default().fg(palette().accent).add_modifier(Modifier::BOLD)
}
pub fn muted_style() -> Style {
    Style::default().fg(palette().muted)
}
