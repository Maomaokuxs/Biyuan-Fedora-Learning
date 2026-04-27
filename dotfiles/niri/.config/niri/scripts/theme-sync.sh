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
    if command -v swww &> /dev/null; then
        swww query &>/dev/null || swww init &>/dev/null
        swww img "$WALLPAPER" --transition-type grow --transition-pos center --transition-duration 2
    fi
else
    echo -e "\033[0;33mℹ️  检测到当前非 Wayland 图形环境，已跳过壁纸实时渲染。\033[0m"
fi

# ==========================================
# 1. 底层取色逻辑 (Hellwal + jq)
# ==========================================
echo ">> 正在分析壁纸色彩..."
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
# 2. 颜色分发矩阵 (仅写文件，绝对安全，不报错)
# ==========================================
echo ">> 正在生成各组件配置文件..."

# --- A. Niri ---
mkdir -p ~/.config/niri
cat <<EOF > ~/.config/niri/colors.kdl
layout {
    focus-ring {
        active-color "$ACCENT"
        inactive-color "$MUTED"
    }
}
EOF

# --- B. Waybar ---
mkdir -p ~/.cache/hellwal
cat <<EOF > ~/.cache/hellwal/colors-waybar.css
@define-color bg $BG;
@define-color fg $FG;
@define-color accent $ACCENT;
@define-color muted $MUTED;
EOF

# --- C. Rofi ---
cat <<EOF > ~/.cache/hellwal/colors-rofi.rasi
* { bg: $BG; fg: $FG; accent: $ACCENT; muted: $MUTED; }
EOF

# --- D. Cava ---
mkdir -p ~/.config/cava
cat <<EOF > ~/.config/cava/config
[input]
method = pulse
source = auto
[color]
background = '$BG'
foreground = '$ACCENT'
EOF

# --- E. Mako ---
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

# --- F. Neovim ---
mkdir -p ~/.config/nvim/lua/utils
cat <<EOF > ~/.config/nvim/lua/utils/theme_colors.lua
local M = {}
M.bg = "$BG"; M.fg = "$FG"; M.accent = "$ACCENT"; M.muted = "$MUTED"
return M
EOF

# --- G. Starship ---
cat <<EOF > ~/.config/starship.toml
format = """\$os\$username\$directory\$git_branch\$git_status\$time\$line_break\$character"""
[os]
disabled = false
format = "[]($ACCENT)[ ](bg:$ACCENT fg:$BG)"
[username]
show_always = true
format = "[ \$user ](bg:$ACCENT fg:$BG)[](fg:$ACCENT bg:$MUTED)"
[directory]
format = "[ \$path ](bg:$MUTED fg:$FG)"
truncation_length = 3
[git_branch]
symbol = ""
format = "[ \$symbol \$branch ](fg:$ACCENT bg:$MUTED)"
[git_status]
format = "[\$all_status\$ahead_behind](fg:$ACCENT bg:$MUTED)"
[time]
disabled = false
format = "[  \$time ](bg:$MUTED fg:$FG)[ ](fg:$MUTED)"
[character]
success_symbol = '[❯](bold fg:$ACCENT)'
error_symbol = '[❯](bold fg:red)'
EOF

# --- H. Hyprlock ---
    mkdir -p ~/.config/hypr

    # 巧妙利用 ${ACCENT:1} 将 #89b4fa 转换为 89b4fa，适配 hyprlock 语法
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
    # 边框使用你的主强调色，内部使用深邃底色
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
    # 每秒更新一次时间
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
    # 每 2 秒抓取一次当前播放的音乐，如果没有播放则显示提示
    text = cmd[update:2000] echo "  \$(playerctl metadata --format '{{ title }}  {{ artist }}' 2>/dev/null || echo 'No Music Playing')"
    color = rgb(${ACCENT:1})
    font_size = 14
    font_family = JetBrainsMono Nerd Font
    position = 0, 30
    halign = center
    valign = bottom
}
EOF



# ==========================================
# 3. 动态热重载逻辑 (仅在图形界面下执行)
# ==========================================
# ==========================================
# 3. 动态热重载逻辑 (仅在图形界面下执行)
# ==========================================
if [ -n "$WAYLAND_DISPLAY" ]; then
    echo ">> 检测到 Wayland 环境，正在热重载桌面组件..."
    
    # 1. 刷新 Niri 自身边框颜色
    niri msg action load-config-file >/dev/null 2>&1 || true
    
    # 2. 【核心修复】：闭包 + 彻底斩断 I/O 联系
    echo ">> 正在下达组件硬重启指令..."
    
    (
        pkill waybar
        pkill cava
        killall mako 2>/dev/null
        
        sleep 0.2
        
        # 重新拉起程序，并将它们的输出也全部丢弃
        waybar >/dev/null 2>&1 &
        mako >/dev/null 2>&1 &
        
    ) </dev/null >/dev/null 2>&1 & disown

    echo -e "\033[0;32m🎉 桌面组件已刷新！\033[0m"
else
    echo -e "\033[0;33mℹ️  当前处于 TTY 环境，跳过进程热重载。\033[0m"
fi














