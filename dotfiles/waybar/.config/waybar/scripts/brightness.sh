#!/bin/bash
# 内接屏亮度：logind SetBrightness（免 root）
BL=/sys/class/backlight/amdgpu_bl1
B=$(cat $BL/brightness); M=$(cat $BL/max_brightness)
STEP=$(( (M * 5 + 50) / 100 ))  # 5% 步进（waybar 独立，quickshell 另有自实现）
set_bl() { busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto \
    org.freedesktop.login1.Session SetBrightness ssu backlight amdgpu_bl1 "$1"; }
case "$1" in
    up)   set_bl $(( B + STEP > M ? M : B + STEP ));;
    down) set_bl $(( B - STEP < 0 ? 0 : B - STEP ));;
    mid)  set_bl $(( (M + 1) / 2 ));;
    *)    p=$(( (B * 100 + M/2) / M )); echo "{\"percentage\": $p}";;
esac
