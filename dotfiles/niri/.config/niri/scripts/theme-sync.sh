#!/bin/bash
# 文件位置: scripts/theme-sync.sh

# ==========================================
# 0. 环境感知与输入检查
# ==========================================
WALLPAPER=$(readlink -f "$1")
if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    echo -e "\033[0;31m❌ 错误: 未提供有效的壁纸路径。\033[0m"
    echo "用法: $0 /路径/到/壁纸.png"
    exit 1
fi

# 检测当前是否运行在 Wayland 图形环境下
if [ -n "$WAYLAND_DISPLAY" ]; then
    if command -v awww &> /dev/null; then
        awww query &>/dev/null || awww init &>/dev/null
        awww img "$WALLPAPER" --transition-type grow --transition-pos center --transition-duration 2
    fi
else
    echo -e "\033[0;33mℹ️  检测到当前非 Wayland 图形环境，已跳过壁纸实时渲染。\033[0m"
fi

# ==========================================
# 1. 内存取色与拦截兜底
# ==========================================
echo ">> 正在分析壁纸色彩 (内存处理)..."
JSON_DATA=$(hellwal -i "$WALLPAPER" -j)

BG=$(echo "$JSON_DATA" | jq -r '.special.background // .colors.color0 // "#1e1e2e"')
FG=$(echo "$JSON_DATA" | jq -r '.special.foreground // .colors.color15 // "#ffffff"')
ACCENT=$(echo "$JSON_DATA" | jq -r '.colors.color4 // "#89b4fa"')
MUTED=$(echo "$JSON_DATA" | jq -r '.colors.color8 // .colors.color0 // "#45475a"')

[[ "$MUTED" == "#000000" || "$MUTED" == "#111111" ]] && MUTED="#2a2b3c"
[[ "$BG" == "#000000" || "$BG" == "#111111" ]] && BG="#1e1e2e"

if [[ ! "$BG" =~ ^# ]] || [[ ! "$ACCENT" =~ ^# ]]; then
    echo -e "\033[0;31m❌ 提取颜色失败。\033[0m"
    exit 1
fi

echo -e "\033[0;32m✨ 调色板生成成功！\033[0m"
echo "   背景: $BG | 文字: $FG | 强调色: $ACCENT | 辅色: $MUTED"

# ==========================================
# 2. 核心：生成全系统唯一的中央色彩数据库
# ==========================================
echo "💾 正在固化中央色彩数据库 -> global-palette.env"
TARGET_DIR="$HOME/.cache/by-mgr/hellwal"
mkdir -p "$TARGET_DIR"
PALETTE_FILE="$TARGET_DIR/global-palette.env"

echo "$JSON_DATA" | jq -r --arg bg "$BG" --arg fg "$FG" --arg acc "$ACCENT" --arg mut "$MUTED" '
  "BG=\"\($bg)\"",
  "FG=\"\($fg)\"",
  "ACCENT=\"\($acc)\"",
  "MUTED=\"\($mut)\"",
  (.colors | to_entries[] | "\(.key | ascii_upcase)=\"\(.value)\"")
' > "$PALETTE_FILE"

echo "   ✔ 中央色彩数据库 -> $PALETTE_FILE"

# ==========================================
# 3. 分发：将唯一数据源映射到各应用配置文件
# ==========================================
echo "🏭 正在为各应用分发色彩配置..."
source "$PALETTE_FILE"

# --- A. Niri (color-niri.kdl) ---
cat <<EOF > "$TARGET_DIR/color-niri.kdl"
layout {
    focus-ring {
        active-color "$ACCENT"
        inactive-color "$MUTED"
    }
}
EOF
echo "   ✔ Niri 配色 -> $TARGET_DIR/color-niri.kdl"

# --- B. Waybar (color-waybar.css) ---
cat <<EOF > "$TARGET_DIR/color-waybar.css"
@define-color bg $BG;
@define-color fg $FG;
@define-color accent $ACCENT;
@define-color muted $MUTED;
EOF
echo "   ✔ Waybar 配色 -> $TARGET_DIR/color-waybar.css"

# --- C. Rofi (color-rofi.rasi) ---
cat <<EOF > "$TARGET_DIR/color-rofi.rasi"
* { bg: $BG; fg: $FG; accent: $ACCENT; muted: $MUTED; }
EOF
echo "   ✔ Rofi 配色 -> $TARGET_DIR/color-rofi.rasi"

# --- D. Cava (Fedora 独有) ---
mkdir -p ~/.config/cava
cat <<EOF > ~/.config/cava/config
[input]
method = pulse
source = auto
[color]
background = '$BG'
foreground = '$ACCENT'
EOF
echo "   ✔ Cava 配色 -> ~/.config/cava/config"

# --- E. Mako (Fedora 独有) ---
mkdir -p ~/.config/mako
cat <<EOF > ~/.config/mako/config
background-color=$BG
text-color=$FG
border-color=$ACCENT
progress-color=over $MUTED
border-size=2
border-radius=8
padding=15
margin=20
font=JetBrainsMono Nerd Font 10
default-timeout=5000
EOF
echo "   ✔ Mako 配色 -> ~/.config/mako/config"

# --- F. Neovim (Fedora 独有) ---
mkdir -p ~/.config/nvim/lua/utils
cat <<EOF > ~/.config/nvim/lua/utils/theme_colors.lua
local M = {}
M.bg = "$BG"; M.fg = "$FG"; M.accent = "$ACCENT"; M.muted = "$MUTED"
return M
EOF
echo "   ✔ Neovim 配色 -> ~/.config/nvim/lua/utils/theme_colors.lua"

# --- G. Starship (归档至中央缓存) ---
echo "🏭 正在为 Starship 分发色彩切片..."

cat << EOF > "$TARGET_DIR/color-starship.toml"
[palettes.hellwal]
bg = "$BG"
fg = "$FG"
accent = "$ACCENT"
muted = "$MUTED"
color0 = "$COLOR0"
color1 = "$COLOR1"
color2 = "$COLOR2"
color3 = "$COLOR3"
color4 = "$COLOR4"
color5 = "$COLOR5"
color6 = "$COLOR6"
color7 = "$COLOR7"
EOF

# 每次换壁纸，永远用干净的 base 模板去拼接颜色，生成最终的 starship.toml
# 优先级: 仓库模板 > 系统配置模板 > by-mgr 本地模板
STARSHIP_BASE=""
if [ -f "$HOME/.config/starship_base.toml" ]; then
    STARSHIP_BASE="$HOME/.config/starship_base.toml"
elif [ -f "$HOME/.config/by-mgr/templates/starship_base.toml" ]; then
    STARSHIP_BASE="$HOME/.config/by-mgr/templates/starship_base.toml"
fi

if [ -f "$STARSHIP_BASE" ]; then
    cat "$STARSHIP_BASE" "$TARGET_DIR/color-starship.toml" > "$HOME/.config/starship.toml"
    echo "   ✔ Starship 配色 -> ~/.config/starship.toml (模板拼接)"
else
    echo "   ⚠️  未找到 starship_base.toml，跳过 Starship 配色"
fi

# --- H. Hyprlock (Fedora 独有) ---
mkdir -p ~/.config/hypr

cat <<EOF > ~/.config/hypr/hyprlock.conf
# 由 theme-sync.sh 自动生成

# 1. 背景：使用当前壁纸，并加上高级的毛玻璃模糊效果
background {
    monitor =
    path = $WALLPAPER
    blur_passes = 3
    blur_size = 8
}

# 2. 密码输入框：极简的胶囊形状
input-field {
    monitor =
    size = 250, 50
    outline_thickness = 2
    dots_size = 0.2
    dots_spacing = 0.6
    dots_center = true
    outer_color = rgb(${ACCENT:1})
    inner_color = rgb(${BG:1})
    font_color = rgb(${FG:1})
    fade_on_empty = false
    placeholder_text = <i>Password...</i>
    hide_input = false
    position = 0, -100
    halign = center
    valign = center
}

# 3. 巨型时间显示
label {
    monitor =
    text = cmd[update:1000] echo "<b><big> \$(date +"%H:%M") </big></b>"
    color = rgb(${FG:1})
    font_size = 94
    font_family = JetBrainsMono Nerd Font
    position = 0, 100
    halign = center
    valign = center
}

# 4. 音乐状态显示 (极简文字呈现)
label {
    monitor =
    text = cmd[update:2000] echo " \$(playerctl metadata --format '{{ title }}  {{ artist }}' 2>/dev/null || echo 'No Music Playing')"
    color = rgb(${ACCENT:1})
    font_size = 14
    font_family = JetBrainsMono Nerd Font
    position = 0, 30
    halign = center
    valign = bottom
}
EOF
echo "   ✔ Hyprlock 配色 -> ~/.config/hypr/hyprlock.conf"

# --- I. Kitty (color-kitty.conf) ---
cat <<EOF > "$TARGET_DIR/color-kitty.conf"
# Kitty color scheme - generated by theme-sync.sh
foreground $FG
background $BG
cursor $ACCENT
selection_foreground $BG
selection_background $ACCENT
EOF

echo "$JSON_DATA" | jq -r '.colors | to_entries[] | "\(.key) \(.value)"' >> "$TARGET_DIR/color-kitty.conf"
echo "   ✔ Kitty 配色 -> $TARGET_DIR/color-kitty.conf"

# ==========================================
# 4. 信号弹：强制引发热重载
# ==========================================
if [ -n "$WAYLAND_DISPLAY" ]; then
    echo ">> 检测到 Wayland 环境，正在热重载桌面组件..."
    
    # 1. 刷新 Niri 自身边框颜色
    niri msg action load-config-file >/dev/null 2>&1 || true
    
    # 2. 重载 Kitty（如果正在运行）
    if command -v kitty &> /dev/null && pgrep -x kitty > /dev/null; then
        kitty @ load-config 2>/dev/null && echo "   ✔ Kitty 配置已重载"
    fi

    # 3. 信号弹方式重载 Waybar 和其他组件
    kill -USR1 $(pidof kitty) 2>/dev/null
    killall -SIGUSR2 waybar 2>/dev/null
    
    echo -e "\033[0;32m🎉 桌面组件已刷新！\033[0m"
else
    echo -e "\033[0;33mℹ️  当前处于 TTY 环境，跳过进程热重载。\033[0m"
fi
