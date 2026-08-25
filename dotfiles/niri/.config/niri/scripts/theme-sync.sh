#!/bin/bash
# theme-sync.sh — 统一配色分发引擎
#
# 依赖: sudo dnf install -y hellwal kde-material-you-colors jq libnotify awww

# 优先级隔离：最低 CPU/IO 优先级，避免取色抢占 awww 渲染（不锁核，交给调度器）
# 哨兵变量防止重执行后再次进入自身（否则无限 exec 循环）
if [ -z "$BY_MGR_NICED" ]; then
    export BY_MGR_NICED=1
    exec nice -n 19 ionice -c 3 bash "$0" "$@"
fi

# 用法: theme-sync.sh [--debug] [--no-render] [wallpaper]
# --no-render: 调用方（如 waypaper）已自行渲染壁纸时，跳过 awww 切换动画，仅同步配色
DEBUG=false; NO_RENDER=false; WALLPAPER_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --debug)     DEBUG=true ;;
        --no-render) NO_RENDER=true ;;
        *)           WALLPAPER_ARG="$1" ;;
    esac
    shift
done
_debug() { $DEBUG && echo "[DEBUG] $(date +%H:%M:%S) $*" >> /tmp/theme-sync-debug.log; }

_debug "========== theme-sync START =========="
_debug "PID=$$ ARG=$WALLPAPER_ARG NO_RENDER=$NO_RENDER"


# ==========================================
# 0. 壁纸检测：传入路径 > 自动检测 > 缓存兜底
# ==========================================
detect_wallpaper() {
    # KDE Plasma 环境下优先读 Plasma 配置
    if pgrep -x plasmashell >/dev/null 2>&1; then
        if [ -f "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" ]; then
            local wp
            wp=$(grep -Po '^Image=\K.*' "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" | head -1)
            if [ -n "$wp" ]; then
                wp="${wp#file://}"
                wp="${wp#file:}"
                [ -n "$wp" ] && [ -f "$wp" ] && echo "$wp" && return 0
fi
        fi
    fi

    # 方法1: waypaper 配置
    if [ -f "$HOME/.config/waypaper/config.ini" ]; then
        local wp
        wp=$(grep -Po '^wallpaper\s*=\s*\K.*' "$HOME/.config/waypaper/config.ini" | head -1)
        wp="${wp/#\~/$HOME}"   # 仅展开 ~，不用 eval（防止文件名含 & 等元字符被截断）
        [ -n "$wp" ] && [ -f "$wp" ] && echo "$wp" && return 0
    fi

    # 方法2: KDE Plasma 配置（兼容 file:// 前缀，非 KDE 环境兜底）
    if [ -f "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" ]; then
        local wp
        wp=$(grep -Po '^Image=\K.*' "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" | head -1)
        if [ -n "$wp" ]; then
            wp="${wp#file://}"
            wp="${wp#file:}"
            [ -n "$wp" ] && [ -f "$wp" ] && echo "$wp" && return 0
        fi
    fi

    # 方法3: 缓存兜底
    if [ -f "$HOME/.cache/by-mgr/last-wallpaper" ]; then
        local wp
        wp=$(cat "$HOME/.cache/by-mgr/last-wallpaper")
        [ -n "$wp" ] && [ -f "$wp" ] && echo "$wp" && return 0
    fi

    return 1
}

WALLPAPER=""
if [ -n "$WALLPAPER_ARG" ] && [ -f "$WALLPAPER_ARG" ]; then
    WALLPAPER=$(readlink -f "$WALLPAPER_ARG")
    _debug "wallpaper arg provided: $WALLPAPER_ARG"
else
    echo ">> 未提供壁纸路径，尝试自动检测..."
    WALLPAPER=$(detect_wallpaper)
fi

if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    _debug "wallpaper detected: $WALLPAPER"
    echo -e "\033[0;31m错误: 无法获取壁纸路径。\033[0m"
    notify-send -i dialog-error "主题同步失败" "无法获取壁纸路径" -t 5000 2>/dev/null &
    exit 1
fi

# 缓存壁纸路径，检测是否真正变更
mkdir -p "$HOME/.cache/by-mgr"
last_wp=$(cat "$HOME/.cache/by-mgr/last-wallpaper" 2>/dev/null)
if [ "$WALLPAPER" == "$last_wp" ]; then
    WALLPAPER_CHANGED=false
else
    WALLPAPER_CHANGED=true
    echo "$WALLPAPER" > "$HOME/.cache/by-mgr/last-wallpaper"
fi

# 检测是否在 KDE Plasma 环境下（避免与 KDE 壁纸管理冲突）
IN_KDE=false
_debug "IN_KDE=$IN_KDE WAYLAND=$WAYLAND_DISPLAY"
if pgrep -x plasmashell >/dev/null 2>&1; then
    IN_KDE=true
fi

# Wayland 壁纸渲染：仅在非 KDE 环境且调用方未自行渲染时执行
if [ -n "$WAYLAND_DISPLAY" ] && ! $IN_KDE && ! $NO_RENDER; then
    if command -v awww &> /dev/null; then
        awww query &>/dev/null || awww init &>/dev/null
        awww img "$WALLPAPER" --transition-type random --transition-pos center --transition-duration 2
    fi
elif $NO_RENDER; then
    echo ">> 调用方已渲染壁纸，跳过切换动画（仅同步配色）"
    _debug "render skipped by --no-render"
elif ! $IN_KDE; then
    echo -e "\033[0;33m检测到当前非 Wayland 图形环境，已跳过壁纸实时渲染。\033[0m"
fi

# ==========================================
# 1. 内存取色与拦截兜底
# ==========================================
echo ">> 正在分析壁纸色彩 (内存处理)..."
# hellwal 的解码器不支持 webp/avif，且扩展名经常是伪装的（png 实为 webp 等）。
# 策略：先直接解码，失败则无条件用 ffmpeg 转码为 png 后重试。
convert_to_png() {
    local src="$1" dst="$2"
    command -v ffmpeg &>/dev/null && timeout 30 ffmpeg -y -loglevel error -i "$src" -frames:v 1 "$dst" 2>/dev/null && [ -s "$dst" ]
}

JSON_DATA=$(hellwal -i "$WALLPAPER" -j 2>/dev/null)
if [ -z "$JSON_DATA" ]; then
    _debug "direct decode failed, converting via ffmpeg"
    TMP_PNG=$(mktemp /tmp/by-mgr-XXXXXX.png)
    if convert_to_png "$WALLPAPER" "$TMP_PNG"; then
        JSON_DATA=$(hellwal -i "$TMP_PNG" -j 2>/dev/null)
    fi
    [ -n "$TMP_PNG" ] && rm -f "$TMP_PNG"
fi
_debug "hellwal returned $(echo $JSON_DATA | wc -c) bytes"

if [ -z "$JSON_DATA" ]; then
    echo -e "\033[0;31mhellwal 无法解析该壁纸（格式不支持或文件损坏），已保留原配色。\033[0m"
    notify-send -i dialog-error "主题同步失败" "hellwal 无法解析: $(basename "$WALLPAPER")" -t 5000 2>/dev/null &
    exit 1
fi

BG=$(echo "$JSON_DATA" | jq -r '.special.background // .colors.color0 // "#1e1e2e"')
FG=$(echo "$JSON_DATA" | jq -r '.special.foreground // .colors.color15 // "#ffffff"')
ACCENT=$(echo "$JSON_DATA" | jq -r '.colors.color4 // "#89b4fa"')
MUTED=$(echo "$JSON_DATA" | jq -r '.colors.color8 // .colors.color0 // "#45475a"')

[[ "$MUTED" == "#000000" || "$MUTED" == "#111111" ]] && MUTED="#2a2b3c"
[[ "$BG" == "#000000" || "$BG" == "#111111" ]] && BG="#1e1e2e"

if [[ ! "$BG" =~ ^# ]] || [[ ! "$ACCENT" =~ ^# ]]; then
    echo -e "\033[0;31m提取颜色失败。\033[0m"
    exit 1
fi

# 对比度守卫：暗色壁纸常抽出近黑的 accent/muted，与背景无法区分。
# 用 WCAG 对比度公式检测，不足时向前景色调和，直到达到最低区分度。
ADJ=$(python3 - "$BG" "$FG" "$ACCENT" "$MUTED" <<'PY'
import sys

def lum(h):
    h = h.lstrip('#')
    lin = lambda c: c/12.92 if c <= 0.03928 else ((c+0.055)/1.055)**2.4
    r, g, b = (lin(int(h[i:i+2], 16)/255) for i in (0, 2, 4))
    return 0.2126*r + 0.7152*g + 0.0722*b

def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la+0.05)/(lb+0.05)

def mix(c1, c2, t):
    c1, c2 = c1.lstrip('#'), c2.lstrip('#')
    return '#' + ''.join(f'{round(int(c1[i:i+2],16)*(1-t)+int(c2[i:i+2],16)*t):02x}' for i in (0, 2, 4))

bg, fg, acc, mut = sys.argv[1:5]
for _ in range(6):
    if ratio(bg, acc) < 1.8: acc = mix(acc, fg, 0.3)
    if ratio(bg, mut) < 1.5: mut = mix(mut, fg, 0.3)
print(acc, mut)
PY
)
ACCENT=$(echo "$ADJ" | cut -d' ' -f1)
MUTED=$(echo "$ADJ" | cut -d' ' -f2)
_debug "contrast guard: ACCENT=$ACCENT MUTED=$MUTED"

echo -e "\033[0;32m调色板生成成功！\033[0m"
_debug "colors: BG=$BG FG=$FG ACCENT=$ACCENT MUTED=$MUTED"
echo "   背景: $BG | 文字: $FG | 强调色: $ACCENT | 辅色: $MUTED"

# 生成 KDE 配色方案
if $IN_KDE && command -v kde-material-you-colors &>/dev/null; then
    echo "正在应用 KDE Plasma Material You 配色..."
    kde-material-you-colors -f "$WALLPAPER" >/dev/null 2>&1 &
    _debug "kde-material-you-colors called"
elif command -v kde-material-you-colors &>/dev/null; then
    echo "正在生成 KDE 配色方案..."
    kde-material-you-colors -f "$WALLPAPER" >/dev/null 2>&1 &
    _debug "kde-material-you-colors (niri) called"
fi

# ==========================================
# 2. 核心：生成全系统唯一的中央色彩数据库
# ==========================================
echo "正在固化中央色彩数据库 -> global-palette.env"
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

echo "   中央色彩数据库 -> $PALETTE_FILE"

# ==========================================
# 3. 分发：将唯一数据源映射到各应用配置文件
# ==========================================
echo "正在为各应用分发色彩配置..."
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
echo "   Niri 配色 -> $TARGET_DIR/color-niri.kdl"

# --- B. Waybar (color-waybar.css) ---
# GLib >= 2.89 按"软链接展开后的真实路径"解析 @import，旧版按加载路径解析。
# 若两者不一致（配置目录为软链接部署，如 stow），运行时在真实路径侧
# 自动维护一个指向真实配色目录的桥接软链接，使两种解析汇聚于同一文件。
cat <<EOF > "$TARGET_DIR/color-waybar.css"
@define-color bg $BG;
@define-color fg $FG;
@define-color accent $ACCENT;
@define-color muted $MUTED;
EOF
STYLE_LOAD_DIR="$(dirname "$HOME/.config/waybar/style.css")"
STYLE_REAL_DIR="$(dirname "$(realpath "$HOME/.config/waybar/style.css" 2>/dev/null)")"
if [ -n "$STYLE_REAL_DIR" ] && [ "$STYLE_REAL_DIR" != "$STYLE_LOAD_DIR" ]; then
    # 仅对单个配色文件做文件级软链接（不链接目录）
    BRIDGE_DIR="$STYLE_REAL_DIR/../../.cache/by-mgr/hellwal"
    if mkdir -p "$BRIDGE_DIR" 2>/dev/null; then
        ln -sfn "$TARGET_DIR/color-waybar.css" "$BRIDGE_DIR/color-waybar.css"
        _debug "bridge file link ensured: $BRIDGE_DIR/color-waybar.css"
    fi
fi
echo "   Waybar 配色 -> $TARGET_DIR/color-waybar.css"

# --- C. Rofi (color-rofi.rasi) ---
cat <<EOF > "$TARGET_DIR/color-rofi.rasi"
* { bg: $BG; fg: $FG; accent: $ACCENT; muted: $MUTED; }
EOF
echo "   Rofi 配色 -> $TARGET_DIR/color-rofi.rasi"

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
echo "   Cava 配色 -> ~/.config/cava/config"

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

[summary="本地系统消息服务"]
invisible=1
EOF
echo "   Mako 配色 -> ~/.config/mako/config"

# --- F. Neovim (Fedora 独有) ---
mkdir -p ~/.config/nvim/lua/utils
cat <<EOF > ~/.config/nvim/lua/utils/theme_colors.lua
local M = {}
M.bg = "$BG"; M.fg = "$FG"; M.accent = "$ACCENT"; M.muted = "$MUTED"
return M
EOF
echo "   Neovim 配色 -> ~/.config/nvim/lua/utils/theme_colors.lua"

# --- G. Starship (归档至中央缓存) ---
echo "正在为 Starship 分发色彩切片..."

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
    echo "   Starship 配色 -> ~/.config/starship.toml (模板拼接)"
else
    echo "   未找到 starship_base.toml，跳过 Starship 配色"
fi

# --- H. Mako (通知配色) ---
cat << EOF > "$TARGET_DIR/color-mako.conf"
background-color=$BG
text-color=$FG
border-color=$MUTED
progress-color=over $ACCENT
EOF
echo "   Mako 配色切片 -> $TARGET_DIR/color-mako.conf"

MAKO_BASE=""
if [ -f "$HOME/.config/mako/config_base" ]; then
    MAKO_BASE="$HOME/.config/mako/config_base"
elif [ -f "$HOME/.config/by-mgr/templates/config_base" ]; then
    MAKO_BASE="$HOME/.config/by-mgr/templates/config_base"
fi

if [ -f "$MAKO_BASE" ]; then
    cat "$MAKO_BASE" "$TARGET_DIR/color-mako.conf" > "$HOME/.config/mako/config"
    echo "   Mako 配色 -> ~/.config/mako/config (模板拼接)"
else
    echo "   未找到 mako 模板，跳过 Mako 配色"
fi

# --- I. Hyprlock (Fedora 独有) ---
mkdir -p ~/.config/hypr

cat <<EOF > ~/.config/hypr/hyprlock.conf
# 由 theme-sync.sh 自动生成

# 1. 背景：使用当前壁纸，并加上高级的毛玻璃模糊效果
background {
    monitor =
    path = "$WALLPAPER"
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
echo "   Hyprlock 配色 -> ~/.config/hypr/hyprlock.conf"

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
echo "   Kitty 配色 -> $TARGET_DIR/color-kitty.conf"

# ==========================================
# 4. 信号弹：强制引发热重载
# ==========================================
if [ -n "$WAYLAND_DISPLAY" ]; then
    echo ">> 检测到 Wayland 环境，正在热重载桌面组件..."
    
    # 1. 刷新 Niri 自身边框颜色
    niri msg action load-config-file >/dev/null 2>&1 || true
    
    # 2. 重载 Kitty（如果正在运行）
    if command -v kitty &> /dev/null && pgrep -x kitty > /dev/null; then
        kitty @ load-config 2>/dev/null && echo "   Kitty 配置已重载"
    fi

    # 3. 信号弹方式重载 Waybar 和其他组件
    kill -USR1 $(pidof kitty) 2>/dev/null
    _debug "waybar pid: $(pgrep -x waybar 2>/dev/null || echo none)"
    # waybar 配置已启用 reload_style_on_change，css 变化自动热重载，无需 SIGUSR2
    _debug "waybar reload signal sent"
    
    echo -e "\033[0;32m桌面组件已刷新！\033[0m"
    [ "$WALLPAPER_CHANGED" = true ] && notify-send -i dialog-ok "主题同步" "配色更新完成" -t 3000 2>/dev/null &
    _debug "notify-send: 配色更新完成"
else
    echo -e "\033[0;33m当前处于 TTY 环境，跳过进程热重载。\033[0m"
    [ "$WALLPAPER_CHANGED" = true ] && notify-send -i dialog-ok "主题同步" "配色文件已生成" -t 3000 2>/dev/null &
fi
