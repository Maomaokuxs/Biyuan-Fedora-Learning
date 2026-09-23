#!/bin/bash
# quickshell-launch.sh — 按持久化记录启动顶栏（niri 自启与 Ctrl+Alt+S 重启键入口）。
# 记录文件由 qs-switch.sh 每次切换时写入；无记录/记录失效回落线上栏。
# 用法: quickshell-launch.sh
STYLE_FILE="$HOME/.cache/by-mgr/qs-barstyle"
LIVE="$HOME/.config/quickshell"
REPO_STYLES="$HOME/.config/quickshell/styles"
LAB="$HOME/Documents/quickshell/bar-lab"

name="$(cat "$STYLE_FILE" 2>/dev/null || echo live)"
case "$name" in
    live|default) dir="$LIVE" ;;
    duo) [ -f "$REPO_STYLES/duo/shell.qml" ] && dir="$REPO_STYLES/duo" || dir="$LIVE" ;;
    *) [ -f "$LAB/$name/shell.qml" ] && dir="$LAB/$name" || dir="$LIVE" ;;
esac
# 同 qs-switch：等旧实例退干净再起，防实例锁冲突
pkill -x quickshell 2>/dev/null
i=0
while pgrep -x quickshell >/dev/null 2>&1 && [ $i -lt 25 ]; do
    sleep 0.2
    i=$((i + 1))
done
quickshell -p "$dir" -d -n & disown
