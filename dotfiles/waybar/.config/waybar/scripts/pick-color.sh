#!/bin/bash
# 像素取色：HEX 复制到剪贴板
if ! command -v hyprpicker >/dev/null 2>&1; then
    notify-send -t 2000 "取色失败" "未安装 hyprpicker"
    exit 1
fi

HEX=$(hyprpicker -b -f hex -s 4 -u 60 2>/dev/null) || exit 0
HEX=${HEX//$'\r'/}
HEX=${HEX//$'\n'/}
[ -z "$HEX" ] && exit 0

if [[ ! "$HEX" =~ ^#[[:xdigit:]]{6}$ ]]; then
    notify-send -t 2000 "取色失败" "无法读取像素颜色"
    exit 1
fi

printf '%s' "$HEX" | wl-copy
notify-send -t 2000 "取色完成" "$HEX 已复制到剪贴板"
