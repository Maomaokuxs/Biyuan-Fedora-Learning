#!/bin/bash
# brightness-set.sh — 设置屏幕亮度（供亮度滑动条松手提交）。
# 用法: brightness-set.sh <internal|external> <0-100>
# 内接屏走 logind SetBrightness（免 root，与 waybar brightness.sh 同机制）；
# 外接屏走 ddcutil（慢，只在松手时调一次）。
mode="$1"
pct="$2"
case "$pct" in ''|*[!0-9]*) exit 1 ;; esac
[ "$pct" -lt 0 ] && pct=0
[ "$pct" -gt 100 ] && pct=100

if [ "$mode" = external ]; then
  ddcutil setvcp 10 "$pct" 2>/dev/null
  exit 0
fi

BL=$(ls -d /sys/class/backlight/* 2>/dev/null | head -1)
[ -z "$BL" ] && exit 1
M=$(cat "$BL/max_brightness" 2>/dev/null)
[ -z "$M" ] && exit 1
RAW=$(( (M * pct + 50) / 100 ))
busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto \
  org.freedesktop.login1.Session SetBrightness ssu backlight "$(basename "$BL")" "$RAW" 2>/dev/null
