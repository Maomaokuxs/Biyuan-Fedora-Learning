#!/bin/bash
# 区域截图：保存到 Screenshots 并复制到剪贴板
DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
FILE="$DIR/截图-$(date +%Y%m%d-%H%M%S).png"
REGION=$(slurp)
[ -z "$REGION" ] && exit 0
grim -g "$REGION" - | tee "$FILE" | wl-copy
notify-send -t 2000 -i "$FILE" "截图完成" "已保存并复制: $(basename "$FILE")"
