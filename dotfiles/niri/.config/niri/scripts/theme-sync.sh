#!/bin/bash
# 文件位置: scripts/theme-sync.sh

# ==========================================
# 1. 环境检查与路径锁定
# ==========================================
WALLPAPER=$(readlink -f "$1")
if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    echo -e "\033[0;31m❌ 错误: 未提供有效的壁纸路径。\033[0m"
    exit 1
fi

# 确保 swww 在运行并切换壁纸
if command -v swww &> /dev/null; then
    swww query &>/dev/null || swww init &>/dev/null
    swww img "$WALLPAPER" --transition-type grow --transition-pos center --transition-duration 2
fi

# ==========================================
# 2. 取色逻辑 (Hellwal + jq)
# ==========================================
JSON_DATA=$(hellwal -i "$WALLPAPER" -j)

BG=$(echo "$JSON_DATA" | jq -r '.special.background // .colors.color0 // "#1e1e2e"')
FG=$(echo "$JSON_DATA" | jq -r '.special.foreground // .colors.color15 // "#ffffff"')
ACCENT=$(echo "$JSON_DATA" | jq -r '.colors.color4 // "#89b4fa"')
MUTED=$(echo "$JSON_DATA" | jq -r '.colors.color8 // .colors.color0 // "#45475a"')

# 亮度补偿：防止纯黑断层
[[ "$MUTED" == "#000000" || "$MUTED" == "#111111" ]] && MUTED="#2a2b3c"
[[ "$BG" == "#000000" || "$BG" == "#111111" ]] && BG="#1e1e2e"

# ==========================================
# 3. 颜色分发矩阵
# ==========================================

# --- A. Niri 窗口边框 ---
mkdir -p ~/.config/niri
cat <<EOF > ~/.config/niri/colors.kdl
layout {
    focus-ring {
        active-color "$ACCENT"
        inactive-color "$MUTED"
    }
}
EOF
niri msg action load-config-file 2>/dev/null || true

# --- B. Waybar 状态栏 ---
mkdir -p ~/.cache/hellwal
cat <<EOF > ~/.cache/hellwal/colors-waybar.css
@define-color bg $BG;
@define-color fg $FG;
@define-color accent $ACCENT;
@define-color muted $MUTED;
EOF
pkill -SIGUSR2 waybar || (pkill waybar; waybar > /dev/null 2>&1 & disown)

# --- C. Starship (已修复语法错误) ---
cat <<EOF > ~/.config/starship.toml
format = """\$os\$username\$directory\$git_branch\$git_status\$time\$character"""

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
# 修复了这里的格式：去掉了多余的嵌套括号
format = "[\$all_status\$ahead_behind](fg:$ACCENT bg:$MUTED)"

[time]
disabled = false
format = "[  \$time ](bg:$MUTED fg:$FG)[ ](fg:$MUTED)"

[character]
success_symbol = '[❯](bold fg:$ACCENT)'
error_symbol = '[❯](bold fg:red)'
EOF

# --- D. Hyprlock 锁屏 ---
mkdir -p ~/.config/hypr
cat <<EOF > ~/.config/hypr/hyprlock.conf
background { monitor = ; path = $WALLPAPER; blur_passes = 3; blur_size = 8 }
input-field {
    size = 250, 50; outline_thickness = 2; dots_center = true
    outer_color = rgb(${ACCENT:1}); inner_color = rgb(${BG:1}); font_color = rgb(${FG:1})
    position = 0, -100; halign = center; valign = center
}
label {
    text = cmd[update:1000] echo "<b><big> \$(date +"%H:%M") </big></b>"
    color = rgb(${FG:1}); font_size = 64; position = 0, 100; halign = center; valign = center
}
EOF

echo "✅ 全系统色彩同步完成！"