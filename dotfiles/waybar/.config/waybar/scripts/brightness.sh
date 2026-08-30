#!/bin/bash
# 内接屏亮度：logind SetBrightness（免 root）
BL=/sys/class/backlight/amdgpu_bl1
B=$(cat $BL/brightness); M=$(cat $BL/max_brightness)
set_bl() { busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto \
    org.freedesktop.login1.Session SetBrightness ssu backlight amdgpu_bl1 "$1"; }
case "$1" in
    up)   set_bl $(( B + 1310 > M ? M : B + 1310 ));;
    down) set_bl $(( B - 1310 < 0 ? 0 : B - 1310 ));;
    mid)  set_bl $(( (M + 1) / 2 ));;
    *)    p=$(( (B * 100 + M/2) / M )); echo "{\"percentage\": $p}";;
esac
