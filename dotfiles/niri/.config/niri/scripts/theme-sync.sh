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

# 0b. 通知管理器探测：看谁真正持有 org.freedesktop.Notifications。
# mako 与 quickshell 自带中心同时只能活一个（dunst 已退役，探测保留），
# 配色分发与重载必须找对正主。返回 mako|dunst|quickshell|none。
detect_notif_manager() {
    local cmd
    cmd=$(busctl --user status org.freedesktop.Notifications 2>/dev/null | grep -m1 '^CommandLine=' | cut -d= -f2-)
    case "$cmd" in
        *mako*) echo mako; return ;;
        *dunst*) echo dunst; return ;;
        *quickshell*) echo quickshell; return ;;
    esac
    if pgrep -x mako >/dev/null 2>&1; then echo mako;
    elif pgrep -x dunst >/dev/null 2>&1; then echo dunst;
    else echo none; fi
}

# 0c. 当前启用的栏：quickshell 还是 waybar（只看进程名）。
# 配色分发只管写文件；要不要发重载信号看它，避免给没跑的栏放空枪。
detect_bar() {
    if pgrep -f "quickshell.*Documents/quickshell" >/dev/null 2>&1; then echo quickshell;
    elif pgrep -x quickshell >/dev/null 2>&1; then echo quickshell;
    elif pgrep -x waybar >/dev/null 2>&1; then echo waybar;
    else echo none; fi
}
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

# 当前接管通知总线的管理器（mako|dunst|quickshell|none），配色分发与重载找正主
NOTIF_MGR=$(detect_notif_manager)
_debug "notification manager: $NOTIF_MGR"
# 当前启用的栏（quickshell|waybar|none），重载信号只发给在跑的那个
BAR=$(detect_bar)
_debug "active bar: $BAR"

if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    _debug "wallpaper detected: $WALLPAPER"
    echo -e "\033[0;31m错误: 无法获取壁纸路径。\033[0m"
    notify-send -i dialog-error "主题同步失败" "无法获取壁纸路径" -t 5000 2>/dev/null &
    exit 1
fi

# 高分辨率优化：只解一次原图生成工作小图（最长边 1024），后续 hellwal/亮度/KDE 全用它
# 同一壁纸直接复用缓存，避免每次 ffmpeg 重解 9K 原图
mkdir -p "$HOME/.cache/by-mgr"
WORK_CACHE="$HOME/.cache/by-mgr/work-small.png"
WORK_CACHE_ID="$HOME/.cache/by-mgr/work-small.id"
WORK_ID=$(stat -c '%d-%i-%s-%Y' "$WALLPAPER" 2>/dev/null)
if [ -f "$WORK_CACHE" ] && [ "$(cat "$WORK_CACHE_ID" 2>/dev/null)" = "$WORK_ID" ]; then
    WORK_SMALL="$WORK_CACHE"
    _debug "work image cache hit"
else
    WORK_SMALL=$(mktemp /tmp/by-mgr-work-XXXXXX.png)
    trap 'rm -f "$WORK_SMALL"' EXIT
    if command -v ffmpeg &>/dev/null; then
        timeout 15 ffmpeg -y -loglevel error -i "$WALLPAPER" -vf "scale=1024:-1" "$WORK_SMALL" 2>/dev/null
    fi
    if [ ! -s "$WORK_SMALL" ]; then
        python3 - "$WALLPAPER" "$WORK_SMALL" <<'PY' 2>/dev/null
import sys
try:
    from PIL import Image
    img = Image.open(sys.argv[1]).convert('RGB')
    img.thumbnail((1024, 1024))
    img.save(sys.argv[2])
except Exception:
    pass
PY
    fi
    if [ -s "$WORK_SMALL" ]; then
        cp -f "$WORK_SMALL" "$WORK_CACHE" 2>/dev/null
        echo "$WORK_ID" > "$WORK_CACHE_ID" 2>/dev/null
    else
        WORK_SMALL="$WALLPAPER"
    fi
    _debug "work image: $WORK_SMALL"
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
# 壁纸未变化时跳过重渲染（9K 图一次 2.7 秒），只做配色同步
if [ -n "$WAYLAND_DISPLAY" ] && ! $IN_KDE && ! $NO_RENDER; then
    if command -v awww &> /dev/null; then
        awww query &>/dev/null || awww init &>/dev/null
        if [ "$WALLPAPER_CHANGED" = true ]; then
            awww img "$WALLPAPER" --transition-type random --transition-pos center --transition-duration 2
        else
            _debug "wallpaper unchanged, skip awww re-render"
        fi
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

JSON_DATA=$(hellwal -i "$WORK_SMALL" -j 2>/dev/null)
if [ -z "$JSON_DATA" ] && [ "$WORK_SMALL" != "$WALLPAPER" ]; then
    _debug "small image decode failed, retry original"
    JSON_DATA=$(hellwal -i "$WALLPAPER" -j 2>/dev/null)
fi
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

# 昼夜联动：夜间用原始深色取色；日间无条件翻为浅色主题（不设亮度阈值）
THEME_NIGHT=false
[ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" = "'prefer-dark'" ] && THEME_NIGHT=true
_debug "theme mode night=$THEME_NIGHT"
if ! $THEME_NIGHT; then
    # 日间浅色：底近白但带壁纸主色，强调直接用粉色系 color5，辅色由强调向底调和
    read AVGHEX < <(python3 - "$WORK_SMALL" <<'PY'
import sys
try:
    from PIL import Image
    img = Image.open(sys.argv[1]).convert('RGB').resize((32, 32))
    px = list(img.getdata())
    n = len(px)
    r = sum(p[0] for p in px) // n; g = sum(p[1] for p in px) // n; b = sum(p[2] for p in px) // n
    print(f'{r:02x}{g:02x}{b:02x}')
except Exception:
    print('808080')
PY
)
    ACCENT5=$(echo "$JSON_DATA" | jq -r '.colors.color5 // .colors.color4 // "#d8979f"')
    read BG FG ACCENT MUTED < <(python3 - "$AVGHEX" "$ACCENT5" <<'PY'
import sys, colorsys
h = sys.argv[1]
r, g, b = (int(h[i:i+2], 16) for i in (0, 2, 4))
bg = tuple(round(c*0.15 + 255*0.85) for c in (r, g, b))
# 文字：取壁纸同色相、明度 0.3 的深灰，绝不用纯黑/近黑；冲突时只调模块色
ah, _, as_ = colorsys.rgb_to_hls(r/255, g/255, b/255)
fr, fg_, fb = colorsys.hls_to_rgb(ah, 0.3, min(as_, 0.5))
fg = (round(fr*255), round(fg_*255), round(fb*255))
acc = sys.argv[2] if sys.argv[2].startswith('#') else '#d8979f'
ah = acc.lstrip('#')
acc = tuple(int(ah[i:i+2], 16) for i in (0, 2, 4))
mut = tuple(round(ac*0.5 + bc*0.5) for ac, bc in zip(acc, bg))
f = lambda t: '#%02x%02x%02x' % t
print(f(bg), f(fg), f(acc), f(mut))
PY
)
    _debug "day light theme: BG=$BG FG=$FG ACCENT=$ACCENT MUTED=$MUTED"
    # Kitty 专用底：只兑 35% 白，保留 65% 壁纸主色，半透明下仍看得出主色调
    KITTY_BG=$(python3 - "$AVGHEX" <<'PY'
import sys
h = sys.argv[1]
r, g, b = (int(h[i:i+2], 16) for i in (0, 2, 4))
print('#%02x%02x%02x' % tuple(round(c*0.65 + 255*0.35) for c in (r, g, b)))
PY
)
    _debug "kitty day bg=$KITTY_BG"
fi

if [[ ! "$BG" =~ ^# ]] || [[ ! "$ACCENT" =~ ^# ]]; then
    echo -e "\033[0;31m提取颜色失败。\033[0m"
    exit 1
fi

# 对比度守卫：accent/muted 既要与背景区分，也要与文字区分
# （uptodate 等模块用色块底配文字色）；不足时分别向另一侧调和。
ADJ=$(python3 - "$BG" "$FG" "$ACCENT" "$MUTED" "$THEME_NIGHT" <<'PY'
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
night = sys.argv[5] == 'true' if len(sys.argv) > 5 else True
for _ in range(6):
    if ratio(bg, acc) < 1.8: acc = mix(acc, fg, 0.3)
    if ratio(bg, mut) < 1.5: mut = mix(mut, fg, 0.3)
    if not night:
        if ratio(fg, acc) < 1.8: acc = mix(acc, bg, 0.3)
        if ratio(fg, mut) < 1.8: mut = mix(mut, bg, 0.3)
print(acc, mut)
PY
)
ACCENT=$(echo "$ADJ" | cut -d' ' -f1)
MUTED=$(echo "$ADJ" | cut -d' ' -f2)
_debug "contrast guard: ACCENT=$ACCENT MUTED=$MUTED"

echo -e "\033[0;32m调色板生成成功！\033[0m"
_debug "colors: BG=$BG FG=$FG ACCENT=$ACCENT MUTED=$MUTED"
echo "   背景: $BG | 文字: $FG | 强调色: $ACCENT | 辅色: $MUTED"

# 生成 KDE 配色方案（跟随昼夜模式显式指定明暗，使 Plasma 与 GNOME 一致，避免 kded 回写 color-scheme）
# 注意：原图可达 9K，直接喂会拖慢 20 秒+甚至 OOM，先缩到 512px 再喂，并加 20 秒超时
KDE_MODE="--light"
$THEME_NIGHT && KDE_MODE="--dark"
KDE_SMALL=$(mktemp /tmp/by-mgr-kde-XXXXXX.png)
python3 - "$WORK_SMALL" "$KDE_SMALL" <<'PY' 2>/dev/null
import sys
try:
    from PIL import Image
    img = Image.open(sys.argv[1]).convert('RGB')
    img.thumbnail((512, 512))
    img.save(sys.argv[2])
except Exception:
    pass
PY
[ -s "$KDE_SMALL" ] || KDE_SMALL="$WALLPAPER"
if $IN_KDE && command -v kde-material-you-colors &>/dev/null; then
    echo "正在应用 KDE Plasma Material You 配色..."
    (setsid timeout -k 5 20 kde-material-you-colors -f "$KDE_SMALL" $KDE_MODE >/dev/null 2>&1 &)
    _debug "kde-material-you-colors called ($KDE_MODE)"
elif command -v kde-material-you-colors &>/dev/null; then
    echo "正在生成 KDE 配色方案..."
    (setsid timeout -k 5 20 kde-material-you-colors -f "$KDE_SMALL" $KDE_MODE >/dev/null 2>&1 &)
    _debug "kde-material-you-colors (niri) called ($KDE_MODE)"
fi
[ "$KDE_SMALL" != "$WALLPAPER" ] && (sleep 60; rm -f "$KDE_SMALL") &>/dev/null &

# ==========================================
# 2. 核心：生成全系统唯一的中央色彩数据库
# ==========================================
# 串行化：曾出现多进程并发导致 palette棕/waybar灰/starship棕交错写；
# 锁只罩住落盘区（2段→J段），慢任务在锁外，不互相掐
mkdir -p "$HOME/.cache/by-mgr"
exec 9>"$HOME/.cache/by-mgr/theme-sync.lock"
# 世代号：快速连点（壁纸卡连击）时只让最后一次落地。
# 慢任务（ffmpeg/hellwal）在锁外并发、耗时不一，若直接串行写盘，
# 先点的可能后写完覆盖——表现为“点了蓝色最后停在粉色”。
# 每次启动先登记世代，进锁后验旧：过期直接静默退出。
RUN_ID="$$-$(date +%s%N)"
echo "$RUN_ID" > "$HOME/.cache/by-mgr/theme-sync.latest"
# 后到为准：锁被占说明有旧实例还在慢任务里转，干掉它们再进，
# 否则旧实例慢悠悠写完会覆盖本次结果、还多发一遍通知。
# 注意不能 pkill -f 裸匹配——自己命令行里也是裸 theme-sync.sh，会自杀；
# 白名单只放过自己($$)和直接父进程($PPID)。
if ! flock -n 9; then
    for _pid in $(pgrep -f "theme-sync\.sh" 2>/dev/null); do
        if [ "$_pid" != "$$" ] && [ "$_pid" != "$PPID" ]; then
            kill "$_pid" 2>/dev/null
        fi
    done
    flock 9
fi
if [ "$(cat "$HOME/.cache/by-mgr/theme-sync.latest" 2>/dev/null)" != "$RUN_ID" ]; then
    echo "已有更新的同步请求，本次结果丢弃"
    exit 0
fi
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

# 中央库附带 RGB 三元组形态（hex 供终端/配置文件，RGB 供 rgba()/rgb()/脚本计算）
python3 - "$PALETTE_FILE" <<'PYEOF'
import sys
p = sys.argv[1]
out = []
for ln in open(p).read().splitlines():
    out.append(ln)
    if '=' in ln:
        k, v = ln.split('=', 1)
        v = v.strip().strip('"')
        if v.startswith('#') and len(v) == 7:
            try:
                r, g, b = (int(v[i:i+2], 16) for i in (1, 3, 5))
                out.append(f'{k}_RGB="{r},{g},{b}"')
            except ValueError:
                pass
open(p, 'w').write('\n'.join(out) + '\n')
PYEOF

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
# 直写 stow 链接的 waybar 真实目录，style.css 同目录即热重载
# 模板重写（仿 starship）：style_base.css（仓库模板）+ 配色 -> style.css
# 优先 stow 链接的真实目录，否则 ~/.config/waybar
WAYBAR_DIR="$(dirname "$(realpath "$HOME/.config/waybar/style.css" 2>/dev/null)")"
[ -z "$WAYBAR_DIR" ] && WAYBAR_DIR="$HOME/.config/waybar"
cat <<EOF > "$WAYBAR_DIR/color-waybar.css"
@define-color bg $BG;
@define-color fg $FG;
@define-color accent $ACCENT;
@define-color muted $MUTED;
EOF
# 用模板重写 style.css 实体（写入即 CLOSE_WRITE，waybar reload_style_on_change 原生热重载）
STYLE_BASE="$WAYBAR_DIR/style_base.css"
if [ -f "$STYLE_BASE" ]; then
    cat "$STYLE_BASE" > "$HOME/.config/waybar/style.css"
    echo "   Waybar style.css 已由模板重写 -> $HOME/.config/waybar/style.css"
fi
echo "   Waybar 配色 -> $WAYBAR_DIR/color-waybar.css"

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

# --- E. Mako (完整主题：全局样式在前，条件段在后) ---
mkdir -p ~/.config/mako
cat <<EOF > ~/.config/mako/config
background-color=$BG
text-color=$FG
border-color=$ACCENT
progress-color=over $ACCENT
border-size=2
border-radius=9
padding=12
margin=18
font=JetBrainsMono Nerd Font 11
default-timeout=5000
max-visible=5

[urgency=low]
border-color=$MUTED
default-timeout=3000

[urgency=critical]
border-color=$FG
background-color=$ACCENT
text-color=$BG
default-timeout=0

[summary="本地系统消息服务"]
invisible=1
EOF
echo "   Mako 主题 -> ~/.config/mako/config"


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

# --- H. Mako 配色切片（仅存档；最终主题由 E 段完整生成） ---
cat << EOF > "$TARGET_DIR/color-mako.conf"
background-color=$BG
text-color=$FG
border-color=$MUTED
progress-color=over $ACCENT
EOF
echo "   Mako 配色切片 -> $TARGET_DIR/color-mako.conf"

# --- I. Hyprlock (Fedora 独有) ---
mkdir -p ~/.config/hypr

# 动态获取屏幕列表 + 焦点屏幕（niri），密码框只在焦点屏生成
HPR_MONITORS=$(niri msg outputs 2>/dev/null | grep 'Output "' | sed 's/.*(\([^)]*\))/\1/' | sort -u)
[ -z "$HPR_MONITORS" ] && HPR_MONITORS="eDP-1"
FOCUS_MONITOR=$(niri msg focused-output 2>/dev/null | sed -n 's/.*(\([^)]*\))/\1/p' | head -1)
[ -z "$FOCUS_MONITOR" ] && FOCUS_MONITOR="eDP-1"

echo "# 由 theme-sync.sh 自动生成（多屏动态，密码框仅在焦点屏）" > ~/.config/hypr/hyprlock.conf
echo "" >> ~/.config/hypr/hyprlock.conf
for mon in $HPR_MONITORS; do
cat >> ~/.config/hypr/hyprlock.conf <<HYPLOCK
# 背景: $mon
background {
    monitor = $mon
    path = $WALLPAPER
    blur_passes = 3
    blur_size = 8
}
HYPLOCK
  if [ "$mon" = "$FOCUS_MONITOR" ]; then
cat >> ~/.config/hypr/hyprlock.conf <<HYPLOCK
# 密码输入框（焦点屏）: $mon
input-field {
    monitor = $mon
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
HYPLOCK
  fi
cat >> ~/.config/hypr/hyprlock.conf <<HYPLOCK
# 时间: $mon
label {
    monitor = $mon
    text = cmd[update:1000] echo "<b><big> \$(date +"%H:%M") </big></b>"
    color = rgb(${FG:1})
    font_size = 94
    font_family = JetBrainsMono Nerd Font
    position = 0, 100
    halign = center
    valign = center
}

# 日期: $mon
label {
    monitor = $mon
    text = cmd[update:60] echo "<b>\$(date +"%Y 年 %m 月 %d 日  %A")</b>"
    color = rgb(${MUTED:1})
    font_size = 18
    font_family = JetBrainsMono Nerd Font
    position = 0, 20
    halign = center
    valign = center
}

HYPLOCK
done
echo "   Hyprlock 配色 -> ~/.config/hypr/hyprlock.conf"

# --- I. Kitty (color-kitty.conf) ---
# 日间底用 KITTY_BG（留 45% 壁纸主色），夜间回落 $BG；
# 亮度>0.8 的色号日间向文字色压暗，保证浅底可读（治白色描边）
cat <<EOF > "$TARGET_DIR/color-kitty.conf"
# Kitty color scheme - generated by theme-sync.sh
foreground $FG
background ${KITTY_BG:-$BG}
cursor $ACCENT
selection_foreground ${KITTY_BG:-$BG}
selection_background $ACCENT
EOF

echo "$JSON_DATA" | jq -r '.colors | to_entries[] | "\(.key) \(.value)"' >> "$TARGET_DIR/color-kitty.conf"
if ! $THEME_NIGHT; then
    python3 - "$TARGET_DIR/color-kitty.conf" "$FG" <<'PYEOF' 2>/dev/null
import sys
p, fg = sys.argv[1], sys.argv[2].lstrip('#')
fr, fgg, fb = (int(fg[i:i+2], 16) for i in (0, 2, 4))
def lum(h):
    h = h.lstrip('#')
    f = lambda c: c/12.92 if c <= 0.03928 else ((c+0.055)/1.055)**2.4
    r, g, b = (f(int(h[i:i+2], 16)/255) for i in (0, 2, 4))
    return 0.2126*r + 0.7152*g + 0.0722*b
out = []
for ln in open(p).read().splitlines():
    parts = ln.split()
    if len(parts) == 2 and parts[0].startswith('color') and parts[1].startswith('#') and lum(parts[1]) > 0.8:
        c = parts[1].lstrip('#')
        mix = (fr, fgg, fb)
        mixed = '#' + ''.join(f'{round(int(c[i:i+2],16)*0.45+mix[i//2]*0.55):02x}' for i in (0, 2, 4))
        out.append(f'{parts[0]} {mixed}')
    else:
        out.append(ln)
open(p, 'w').write('\n'.join(out) + '\n')
PYEOF
    _debug "kitty brights remapped for day"
fi
echo "   Kitty 配色 -> $TARGET_DIR/color-kitty.conf"

# --- J. Fcitx5 (waybar-hud 浅+深两套皮肤：读中央库 global-palette.env 重生成) ---
FCITX_SYNC="${FCITX_SYNC:-$HOME/Documents/fcitx5/sync-waybar.sh}"
if [ -x "$FCITX_SYNC" ]; then
    WAYBAR_CSS="$WAYBAR_DIR/color-waybar.css" bash "$FCITX_SYNC" --install \
        && echo "   Fcitx5 皮肤已跟随配色" \
        || echo "   ( Fcitx5 皮肤同步跳过)"
else
    echo "   未找到 fcitx5 皮肤生成器 ($FCITX_SYNC)，跳过 Fcitx5 配色"
fi

# 收尾：中央库与 waybar 落盘一致性校验 + 释放串行锁
PB=$(grep -oP '^BG="\K[^"]+' "$PALETTE_FILE" 2>/dev/null); WB=$(grep -oP '@define-color bg \K[^;]+' "$WAYBAR_DIR/color-waybar.css" 2>/dev/null)
[ -n "$PB" ] && [ "$PB" = "$WB" ] && echo "   中央库校验一致 ($PB)" || echo -e "   \033[0;33m中央库与 waybar 待对齐，见上文各段输出\033[0m"
exec 9>&-

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
    # 3.5 重载通知配色：只找 NOTIF_MGR 正主（quickshell 系绑定 theme.* 实时跟，无需重载）
    case "$NOTIF_MGR" in
        mako) makoctl reload >/dev/null 2>&1 && echo "   ✔ Mako 配置已重载" ;;
        # quickshell 系绑定 theme.* 实时跟，无需重载；dunst 已退役
        *) _debug "notification reload skipped ($NOTIF_MGR)" ;;
    esac
    # waybar reload_style_on_change 监听 style.css 与 @import 链，color-waybar.css 直写同目录 + touch 即自动重载。
    # 只在 waybar 在跑时放信号弹（配色文件照写，切回去即时可用）。
    if [ "$BAR" = waybar ]; then
        touch "$HOME/.config/waybar/style.css" 2>/dev/null || true
        _debug "waybar reload via style reload_style_on_change"
    else
        _debug "waybar reload skipped (bar=$BAR)"
    fi
    
    echo -e "\033[0;32m桌面组件已刷新！\033[0m"
    [ "$WALLPAPER_CHANGED" = true ] && notify-send -i dialog-ok "主题同步" "配色更新完成" -t 3000 2>/dev/null & true
    _debug "notify-send: 配色更新完成"
else
    echo -e "\033[0;33m当前处于 TTY 环境，跳过进程热重载。\033[0m"
    [ "$WALLPAPER_CHANGED" = true ] && notify-send -i dialog-ok "主题同步" "配色文件已生成" -t 3000 2>/dev/null & true
fi

# 正常完成（_debug 在 DEBUG=false 时返回非零，不代表失败）
exit 0
