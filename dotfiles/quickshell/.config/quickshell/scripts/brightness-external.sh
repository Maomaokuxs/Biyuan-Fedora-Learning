#!/bin/bash
# brightness-external.sh — 外接屏亮度（ddcutil），对齐 waybar custom/backlight。
# 从 Bar.qml 内联命令拆出：内联写法里 awk "{print $4}" 的 $4 会被外层 sh -c 吃掉，
# 导致整行 ddcutil 输出直接上屏。独立文件无此问题。
val=$(ddcutil getvcp 10 --brief 2>/dev/null | awk '{print $4}')
case "$val" in ''|*[!0-9]*) val=50 ;; esac
printf '{"text":"󰃟 %s%%"}' "$val"
