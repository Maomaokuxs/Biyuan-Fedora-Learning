#!/bin/bash
# 屏幕守护：screen.sh 选了「仅第二屏幕（外接）」后，/tmp/screen_state/internal 标记存在。
# 若此时外接屏被拔掉，niri 不会自动重新开启被 off 的 eDP-1，笔记本会黑屏失联。
# 本守护轮询 outputs：标记在、外接屏不在 → 开启 eDP-1 并清标记。
# 用法: screen-guard.sh          常驻轮询（niri spawn-at-startup 拉起）
#       screen-guard.sh --once   只检查一轮（测试用）
# 环境: EXT_NAME 覆盖外接屏名（默认 HDMI-A-1）；DRY_RUN=1 只打印不执行
DIR=/tmp/screen_state
INT_NAME=eDP-1
EXT_NAME="${EXT_NAME:-HDMI-A-1}"

exec 9>/tmp/screen-guard.lock
flock -n 9 || exit 0

find_socket() {
    NIRI_SOCKET=$(ls /run/user/"$(id -u)"/niri.*.sock 2>/dev/null | head -1)
    export NIRI_SOCKET XDG_RUNTIME_DIR=/run/user/"$(id -u)"
    [ -n "$NIRI_SOCKET" ]
}

check_once() {
    [ -f "$DIR/internal" ] || return 0
    find_socket || return 0
    local outs
    outs=$(niri msg -j outputs 2>/dev/null) || return 0
    if ! grep -q "\"$EXT_NAME\"" <<< "$outs"; then
        if [ "$DRY_RUN" = 1 ]; then
            echo "[dry-run] $EXT_NAME 已断开，将执行: niri msg output $INT_NAME on; rm -f $DIR/internal"
        else
            niri msg output "$INT_NAME" on 2>/dev/null
            rm -f "$DIR/internal"
            notify-send -t 3000 "屏幕模式" "外接屏已断开，已恢复内屏" 2>/dev/null
        fi
    fi
}

if [ "$1" = "--once" ]; then
    check_once
else
    while true; do
        check_once
        sleep 3
    done
fi
