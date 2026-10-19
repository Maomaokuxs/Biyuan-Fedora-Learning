#!/bin/bash
# 护眼模式开关：toggle gammastep -O 4500，并把状态持久化到 ~/.cache/by-mgr/gammastep-on（1=开/0=关），
# quickshell 启动时由 gammastep-restore.sh 读回恢复。
STATE_FILE="$HOME/.cache/by-mgr/gammastep-on"
mkdir -p "$(dirname "$STATE_FILE")"
if pgrep -x gammastep >/dev/null; then
  pkill gammastep && printf "0" > "$STATE_FILE" && notify-send "护眼" "已关闭"
else
  if ! command -v gammastep >/dev/null; then
    notify-send "护眼" "gammastep未安装，请安装 gammastep 软件包"
  else
    gammastep -O 4500 >/tmp/gammastep.log 2>&1 &
    sleep 1
    if pgrep -x gammastep >/dev/null; then
      printf "1" > "$STATE_FILE" && notify-send "护眼" "已开启"
    else
      printf "0" > "$STATE_FILE"
      ERR=$(tail -1 /tmp/gammastep.log 2>/dev/null)
      notify-send "护眼" "启动失败: $ERR"
    fi
  fi
fi
