#!/bin/bash
# inhibit.sh — 包装 waybar inhibit.sh：原脚本 echo 不解释 \u，会输出字面量，需转成真字形
out=$(bash ~/.config/waybar/scripts/inhibit.sh "$@" 2>/dev/null)
printf '%s' "$out" | sed -e 's/\\uf023//g' -e 's/\\uf09c//g'
