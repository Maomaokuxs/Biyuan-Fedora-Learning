#!/bin/bash
# qs-switch.sh — 线上栏与 lab 样式之间自由切换（一次只活一个）。
# 用法: qs-switch.sh [default|<风格名>|next]
#   default = 线上栏 (~/.config/quickshell)，风格名 = 动态扫描（仓库 styles/＋bar-lab），next = 按表轮换。
# 建议绑 niri 快捷键（示例，手工加到 config.kdl）：
#   Mod+Shift+B { spawn "bash ~/Documents/quickshell/bar-lab/qs-switch.sh next"; }
LAB="$HOME/Documents/quickshell/bar-lab"
LIVE="$HOME/.config/quickshell"
# duo 已进主仓库（styles/ 独立目录），其余风格仍在 bar-lab
REPO_STYLES="$HOME/.config/quickshell/styles"
# 风格表：只要三套 default / duo（+ waybar 走 toggle-bar，不在这里）
ORDER=(default duo)

cur_dir() { pgrep -af "^quickshell -p " 2>/dev/null | head -n 1 | sed -n 's/.*-p \([^ ]*\).*/\1/p'; }
cur_name() {
    local d; d="$(cur_dir)"
    [ -z "$d" ] && { echo none; return; }
    [ "$d" = "$LIVE" ] && { echo default; return; }
    basename "$d"
}
launch() {
    local dir="$1" name="$2"
    # 持久化：下次开机/重启键读这个文件恢复同款
    printf '%s' "$name" > "$HOME/.cache/by-mgr/qs-barstyle"
    # 切回线上时顺手清 waybar/mako（和 toggle-bar.sh 同语义），风格之间切不用
    if [ "$name" = default ]; then
        pkill waybar 2>/dev/null; pkill cava 2>/dev/null
        systemctl --user stop mako 2>/dev/null
        pkill -x mako 2>/dev/null
    fi
    pkill -x quickshell 2>/dev/null
    # 等旧实例真退出再起新的（layer-shell/实例锁释放慢半拍，
    # 睡眠固定值会撞锁导致新实例起不来、两头落空）
    local i=0
    while pgrep -x quickshell >/dev/null 2>&1 && [ $i -lt 25 ]; do
        sleep 0.2
        i=$((i + 1))
    done
    quickshell -p "$dir" -d -n & disown
    notify-send -t 1500 "quickshell" "已切换到 $name" 2>/dev/null
    echo "switched to $name ($dir)"
}

target="$1"
[ -z "$target" ] && target="next"
if [ "$target" = next ]; then
    cur="$(cur_name)"
    idx=-1
    for i in "${!ORDER[@]}"; do [ "${ORDER[$i]}" = "$cur" ] && idx=$i && break; done
    target="${ORDER[$(( (idx + 1) % ${#ORDER[@]} ))]}"
fi
if [ "$target" = default ]; then
    launch "$LIVE" default
elif [ "$target" = duo ] && [ -f "$REPO_STYLES/duo/shell.qml" ]; then
    launch "$REPO_STYLES/duo" "duo"
elif [ -f "$LAB/$target/shell.qml" ]; then
    launch "$LAB/$target" "$target"
else
    echo "unknown style: $target (lab/$target/shell.qml 不存在)" >&2
    echo "current: $(cur_name)" >&2
    exit 1
fi
