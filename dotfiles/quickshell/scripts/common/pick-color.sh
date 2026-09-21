#!/bin/bash
# 像素取色：HEX 复制到剪贴板
HEX=$(grim -g "$(slurp -p)" -t png - | magick txt:- | grep -oE '#[0-9A-Fa-f]{6}' | head -1)
[ -z "$HEX" ] && exit 0
printf '%s' "$HEX" | wl-copy
notify-send -t 2000 "取色完成" "$HEX 已复制到剪贴板"
