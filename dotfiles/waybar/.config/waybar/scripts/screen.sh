#!/bin/bash
# 屏幕模式统一脚本（仿 Win+P）
# 用法: screen.sh         → 输出状态 JSON（供模块显示）
#       screen.sh menu    → rofi 屏幕模式菜单
DIR=/tmp/screen_state
mkdir -p "$DIR"

status() {
    INT=on; EXT=on
    [ -f "$DIR/internal" ] && INT=off
    [ -f "$DIR/external" ] && EXT=off
    if [ "$INT" = on ] && [ "$EXT" = on ]; then cls=on
    elif [ "$INT" = off ] && [ "$EXT" = off ]; then cls=off
    elif [ "$INT" = off ]; then cls=internal
    else cls=external; fi
    echo "{\"text\": \"󰅶\", \"class\": \"$cls\"}"
}

menu() {
    CHOICE=$(echo -e "扩展模式（两块屏）\n仅电脑屏幕（内接）\n仅第二屏幕（外接）" | rofi -dmenu -i -p "屏幕模式")
    case "$CHOICE" in
        扩展模式*)
            niri msg output eDP-1 on 2>/dev/null
            niri msg output HDMI-A-1 on 2>/dev/null
            rm -f "$DIR/internal" "$DIR/external" ;;
        仅电脑屏幕*)
            niri msg output eDP-1 on 2>/dev/null
            niri msg output HDMI-A-1 off 2>/dev/null
            rm -f "$DIR/internal"; touch "$DIR/external" ;;
        仅第二屏幕*)
            niri msg output HDMI-A-1 on 2>/dev/null
            niri msg output eDP-1 off 2>/dev/null
            rm -f "$DIR/external"; touch "$DIR/internal" ;;
        *) exit 0 ;;
    esac
    notify-send -t 1500 "屏幕模式" "已切换: ${CHOICE%%（*}"
}

case "$1" in
    menu) menu ;;
    *) status ;;
esac
