#!/bin/bash
DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
TMP=$(mktemp /tmp/screenshot-XXXX.png)
REGION=$(slurp)
[ -z "$REGION" ] && rm -f "$TMP" && exit 0
grim -g "$REGION" "$TMP"
swappy -f "$TMP"
# swappy 会直接修改 $TMP，保存后复制
if [ -f "$TMP" ]; then
    FILE="$DIR/Screenshot-$(date +%Y%m%d-%H%M%S).png"
    cp "$TMP" "$FILE"
    wl-copy < "$FILE"
    notify-send -t 2000 -i "$FILE" "截图完成" "已保存并复制: $(basename "$FILE")"
    rm -f "$TMP"
fi
