#!/bin/bash
# brightness.sh — 内接屏亮度（quickshell 自有实现，不依赖 waybar 脚本）。
# sysfs 读 + logind SetBrightness 写（免 root），步进 5%（waybar 原版约 2%，各管各的）。
# 输出 {"text":"<icon> NN%"} 供 BarState.bri；up/down/mid 供滚轮/右键。
BL=/sys/class/backlight/amdgpu_bl1
B=$(cat $BL/brightness 2>/dev/null || echo 0); M=$(cat $BL/max_brightness 2>/dev/null || echo 65535)
[ "$M" -gt 0 ] 2>/dev/null || M=65535
STEP=$(( (M * 5 + 50) / 100 ))
set_bl() { busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto \
    org.freedesktop.login1.Session SetBrightness ssu backlight amdgpu_bl1 "$1" >/dev/null 2>&1; }
case "$1" in
    up) set_bl $(( B + STEP > M ? M : B + STEP )); B=$(cat $BL/brightness 2>/dev/null || echo "$B") ;;
    down) set_bl $(( B - STEP < 0 ? 0 : B - STEP )); B=$(cat $BL/brightness 2>/dev/null || echo "$B") ;;
    mid) set_bl $(( (M + 1) / 2 )); B=$(cat $BL/brightness 2>/dev/null || echo "$B") ;;
esac
p=$(( (B * 100 + M/2) / M ))
[ -z "$p" ] && p=50
if [ "$p" -lt 34 ]; then icon="󰃞"; elif [ "$p" -lt 67 ]; then icon="󰃟"; else icon="󰃠"; fi
printf '{"text":"%s %s%%"}' "$icon" "$p"
