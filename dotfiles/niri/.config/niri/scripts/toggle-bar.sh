#!/bin/bash
# toggle-bar.sh — waybar <-> quickshell 一键切换（二者只跑一个）
# 配套 theme-sync.sh 的 detect_bar()：切完后配色重载信号自动找对正主。
# 用法：toggle-bar.sh [refresh] — refresh 按当前在跑的栏做刷新
#   （quickshell 在跑就重启它，waybar 在跑就重载它；都没跑则起 quickshell）。
QS_PAT="quickshell -p"

detect_bar() {
    if pgrep -f "$QS_PAT" >/dev/null 2>&1; then echo quickshell;
    elif pgrep -x quickshell >/dev/null 2>&1; then echo quickshell;
    elif pgrep -x waybar >/dev/null 2>&1; then echo waybar;
    else echo none; fi
}

wait_gone() {
    # 等进程真正退出（最多 5s），避免新旧实例重叠抢通知总线
    local pat="$1" i=0
    while pgrep -f "$pat" >/dev/null 2>&1 && [ $i -lt 25 ]; do
        sleep 0.2
        i=$((i + 1))
    done
}

refresh_bar() {
    case "$(detect_bar)" in
        waybar)
            pkill waybar 2>/dev/null; pkill cava 2>/dev/null; pkill sed 2>/dev/null
            waybar & disown ;;
        *)
            # 先清 mako（否则它占着通知总线，quickshell 接管不回来）
            systemctl --user stop mako 2>/dev/null
            pkill -x mako 2>/dev/null
            # 刷新不断风格：先记下当前在跑的 -p 路径再杀，起回同一个；
            # 记不到才走 launcher（读持久化记录）
            cur="$(pgrep -af '^quickshell -p' | head -n 1 | sed -n 's/.*-p \([^ ]*\).*/\1/p')"
            pkill -x quickshell 2>/dev/null
            wait_gone "$QS_PAT"
            if [ -n "$cur" ]; then
                quickshell -p "$cur" -d -n & disown
            else
                bash ~/.config/niri/scripts/quickshell-launch.sh
            fi ;;
    esac
}

if [ "$1" = "refresh" ]; then
    refresh_bar
    exit 0
fi

if [ "$(detect_bar)" = "quickshell" ]; then
    pkill -x quickshell
    wait_gone "$QS_PAT"
    pkill waybar 2>/dev/null; pkill cava 2>/dev/null; pkill sed 2>/dev/null
    waybar & disown
else
    pkill waybar 2>/dev/null; pkill cava 2>/dev/null; pkill sed 2>/dev/null
    systemctl --user stop mako 2>/dev/null
    pkill -x mako 2>/dev/null
    # 经 launcher 回切：恢复持久化的风格（无记录回落线上栏）
    bash ~/.config/niri/scripts/quickshell-launch.sh
    notify-send "顶栏" "已切换到 quickshell" -t 2000 2>/dev/null &
fi
