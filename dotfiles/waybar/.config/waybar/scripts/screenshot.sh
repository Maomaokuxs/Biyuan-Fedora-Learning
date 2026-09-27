#!/bin/bash
DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
TMP=$(mktemp /tmp/screenshot-XXXX.png)
REGION=$(slurp)
[ -z "$REGION" ] && rm -f "$TMP" && exit 0
grim -g "$REGION" "$TMP"
if command -v swappy &>/dev/null; then
    # 有 swappy：标注/保存/复制全交给他（save_dir 已配到截图目录）
    swappy -f "$TMP"
    rm -f "$TMP"
else
    # 无 swappy：自动落盘 + 进剪贴板
    FILE="$DIR/Screenshot-$(date +%Y%m%d-%H%M%S).png"
    cp "$TMP" "$FILE"
    wl-copy < "$FILE"
    notify-send -t 2000 -i "$FILE" "截图完成" "已保存并复制: $(basename "$FILE")"
    rm -f "$TMP"
fi
