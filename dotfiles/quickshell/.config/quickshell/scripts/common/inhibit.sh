#!/bin/bash
# 阻止熄屏模块：fa-eye 真眼睛图标（Pango 下可靠渲染）
FLAG=/tmp/inhibit_flag

status() {
    if [ -f "$FLAG" ] && kill -0 $(cat "$FLAG" 2>/dev/null) 2>/dev/null; then
        echo "{\"text\": \"\uf023\", \"class\": \"inhibited\"}"
    else
        rm -f "$FLAG"
        echo "{\"text\": \"\uf09c\", \"class\": \"idle\"}"
    fi
}

toggle() {
    if [ -f "$FLAG" ] && kill -0 $(cat "$FLAG" 2>/dev/null) 2>/dev/null; then
        kill $(cat "$FLAG") 2>/dev/null
        rm -f "$FLAG"
        notify-send -t 1000 "熄屏" "已允许熄屏"
    else
        rm -f "$FLAG"
        systemd-inhibit --what=idle --who=waybar --why="阻止熄屏" sleep infinity &
        echo $! > "$FLAG"
        notify-send -t 1000 "熄屏" "已阻止熄屏"
    fi
}

case "$1" in
    toggle) toggle ;;
    *) status ;;
esac
