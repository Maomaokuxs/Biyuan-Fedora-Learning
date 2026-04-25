#!/bin/bash

# ==========================================
# 1. 路径转换与壁纸切换
# ==========================================
WALLPAPER=$(realpath "$1")
[ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ] && echo "用法: $0 /路径/到/壁纸.png" && exit 1

# 接收从 Waypaper 传来的第一个参数（壁纸路径）
WALLPAPER=$1

if [ ! -f "$WALLPAPER" ]; then
    exit 1
fi


# 切换壁纸 (swww)
swww img "$WALLPAPER" --transition-type grow --transition-pos center --transition-duration 2

# ==========================================
# 2. 底层取色逻辑 (Hellwal + jq)
# ==========================================
JSON_DATA=$(hellwal -i "$WALLPAPER" -j)

# 提取多维度色彩
BG=$(echo "$JSON_DATA" | jq -r '.special.background // .colors.color0 // "#1e1e2e"')
FG=$(echo "$JSON_DATA" | jq -r '.special.foreground // .colors.color15 // "#ffffff"')
ACCENT=$(echo "$JSON_DATA" | jq -r '.colors.color4 // "#89b4fa"')
MUTED=$(echo "$JSON_DATA" | jq -r '.colors.color8 // .colors.color0 // "#45475a"')

# 终极安全锁 (防止空值或 null)
[[ -z "$BG" || "$BG" == "null" ]] && BG="#1e1e2e"
[[ -z "$FG" || "$FG" == "null" ]] && FG="#ffffff"
[[ -z "$ACCENT" || "$ACCENT" == "null" ]] && ACCENT="#89b4fa"
[[ -z "$MUTED" || "$MUTED" == "null" ]] && MUTED="#45475a"

# ==========================================
# 3. 颜色分发矩阵
# ==========================================
if [[ "$BG" =~ ^# ]] && [[ "$ACCENT" =~ ^# ]]; then
    echo "✨ 调色板生成成功！"
    echo "背景: $BG | 文字: $FG | 强调色: $ACCENT | 辅色: $MUTED"

    # --- A. 分发给 Niri (窗口管理器) ---
    cat <<EOF > ~/.config/niri/colors.kdl
layout {
    focus-ring {
        active-color "$ACCENT"
        inactive-color "$MUTED"
    }
}
EOF
    niri msg action load-config-file

    # --- B. 分发给 Waybar (状态栏) ---
    mkdir -p ~/.cache/hellwal
    cat <<EOF > ~/.cache/hellwal/colors-waybar.css
@define-color bg $BG;
@define-color fg $FG;
@define-color accent $ACCENT;
@define-color muted $MUTED;
EOF
    pkill waybar; waybar > /dev/null 2>&1 & disown

    # --- C. 分发给 Rofi (启动器) ---
    cat <<EOF > ~/.cache/hellwal/colors-rofi.rasi
* {
    bg: $BG;
    fg: $FG;
    accent: $ACCENT;
    muted: $MUTED;
}
EOF

    # --- D. 分发给 Cava (频谱分析) ---
    mkdir -p ~/.config/cava
    cat <<EOF > ~/.config/cava/config
[input]
method = pulse
source = auto

[color]
background = '$BG'
foreground = '$ACCENT'
EOF
    pkill -USR1 cava || true

    # --- E. 分发给 Mako (通知系统) ---
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

[urgency=critical]
border-color=#E64553
default-timeout=0
EOF
    makoctl reload > /dev/null 2>&1 || (mako > /dev/null 2>&1 & disown)

    # --- F. 分发给 Neovim (色彩矩阵) ---
    mkdir -p ~/.config/nvim/lua/utils
    cat <<EOF > ~/.config/nvim/lua/utils/theme_colors.lua
-- 由系统色彩脚本自动生成
local M = {}
M.bg = "$BG"      -- 背景色
M.fg = "$FG"      -- 前景色
M.accent = "$ACCENT" -- 强调色
M.muted = "$MUTED"   -- 辅色
return M
EOF

    # ==========================================
    # --- G. 分发给 Starship (终极防断层 Powerline) ---
    # ==========================================

    # 🟢 强力亮度补丁：拦截纯黑，彻底防止终端透明穿透！
    [[ "$MUTED" == "#000000" || "$MUTED" == "#111111" ]] && MUTED="#2a2b3c"
    [[ "$BG" == "#000000" || "$BG" == "#111111" ]] && BG="#1e1e2e"

    cat <<EOF > ~/.config/starship.toml
# 由 theme-sync.sh 自动生成 - 完美解决孤儿三角与透明穿透

# 1. 全局布局：干掉所有硬编码的三角形，让模块自我管理！
format = """
\$os\
\$username\
\$directory\
\$git_branch\
\$git_status\
\$nodejs\
\$python\
\$c\$rust\$golang\
\$time\
\$cmd_duration\
\$line_break\
\$character"""

[os]
disabled = false
# 开头自带左圆角 
format = "[]($ACCENT)[ ](bg:$ACCENT fg:$BG)"

[username]
show_always = true
# 核心魔法：用户名结束后，自带向右的三角符号 ，平滑过渡到 MUTED 颜色
format = "[ \$user ](bg:$ACCENT fg:$BG)[](fg:$ACCENT bg:$MUTED)"

[directory]
# 目录以及后面的模块全部统一使用 MUTED 背景，消除多余的色块断层
format = "[ \$path ](bg:$MUTED fg:$FG)"
truncation_length = 3
truncation_symbol = "…/"

[git_branch]
symbol = ""
# Git 等动态模块保持背景一致，只用高亮颜色 (ACCENT) 突出图标，极其优雅
format = "[ \$symbol \$branch ](fg:$ACCENT bg:$MUTED)"

[git_status]
format = "[[(\$all_status\$ahead_behind )]](fg:$ACCENT bg:$MUTED)"

[nodejs]
symbol = ""
format = "[ \$symbol( \$version) ](fg:$ACCENT bg:$MUTED)"

[python]
symbol = ""
format = "[ \$symbol( \$version) ](fg:$ACCENT bg:$MUTED)"

[time]
disabled = false
time_format = "%R"
# 结尾自带右圆角 ，完美收尾
format = "[  \$time ](bg:$MUTED fg:$FG)[ ](fg:$MUTED)"

[character]
success_symbol = '[❯](bold fg:$ACCENT)'
error_symbol = '[❯](bold fg:red)'
EOF

    # ==========================================
    # --- H. 分发给 Hyprlock (极简动态锁屏) ---
    # ==========================================
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

# 2. 手动生成一个通用的 GTK CSS 变量文件
cat <<EOF > "$HOME/.cache/hellwal/colors-gtk.css"
@define-color accent ${color1};
@define-color bg_color ${background};
@define-color fg_color ${foreground};
@define-color muted ${color8};
EOF


echo "🎉 全系统矩阵（Niri/Waybar/Rofi/Cava/Mako/Neovim/Starship）同步完成！"

else
    echo "❌ 提取颜色失败，请检查 Hellwal 状态或壁纸路径。"
    exit 1
fi
