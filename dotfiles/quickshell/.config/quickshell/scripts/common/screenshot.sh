#!/bin/bash
SAVEDIR="$HOME/Pictures/Screenshots"
mkdir -p "$SAVEDIR"
# 记录 swappy 打开前最新的文件，用于判断是否有新保存
BEFORE=$(ls -t "$SAVEDIR" 2>/dev/null | head -1)
TMP=$(mktemp /tmp/screenshot-XXXX.png)
REGION=$(slurp)
[ -z "$REGION" ] && rm -f "$TMP" && exit 0
grim -g "$REGION" "$TMP"
swappy -f "$TMP"
rm -f "$TMP"
# 检查是否有新文件被保存
AFTER=$(ls -t "$SAVEDIR" 2>/dev/null | head -1)
if [ -n "$AFTER" ] && [ "$BEFORE" != "$AFTER" ]; then
    FILE="$SAVEDIR/$AFTER"
    # 确认是刚保存的（1分钟内）
    if [ $(($(date +%s) - $(stat -c %Y "$FILE"))) -lt 60 ]; then
        notify-send -t 3000 -i "$FILE" "截图已保存" "$(basename "$FILE")"
    fi
fi
