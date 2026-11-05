#!/bin/bash
# 屏幕模式统一脚本（仿 Win+P），改由 kanshi/kanshictl 驱动（2026-11-05）
# 直接调 niri msg 改输出会被 kanshi 按 profile 改回去，所以菜单只发 kanshictl 命令。
# 用法: screen.sh         → 输出状态 JSON（供模块显示）
#       screen.sh menu    → rofi 屏幕模式菜单
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"

status() {
    local prof
    prof=$(kanshictl status 2>/dev/null | sed -n 's/^Current profile: //p')
    case "$prof" in
        docked)   cls=external; icon="󰔂" ;;
        laptop|internal) cls=internal; icon="󰌢" ;;
        extend)   cls=on; icon="󰍹" ;;
        *)        cls=off; icon="󰍹" ;;
    esac
    echo "{\"text\": \"$icon\", \"tooltip\": \"屏幕常亮\", \"class\": \"$cls\"}"
}

menu() {
    CHOICE=$(echo -e "自动（跟随插拔）\n扩展模式（两块屏）\n仅电脑屏幕（内接）\n仅第二屏幕（外接）" | rofi -dmenu -i -p "屏幕模式")
    case "$CHOICE" in
        自动*) kanshictl reload ;;
        扩展模式*) kanshictl switch extend ;;
        仅电脑屏幕*) kanshictl switch internal ;;
        仅第二屏幕*) kanshictl switch docked ;;
        *) exit 0 ;;
    esac
    notify-send -t 1500 "屏幕模式" "已切换: ${CHOICE%%（*}"
}

case "$1" in
    menu) menu ;;
    *) status ;;
esac
