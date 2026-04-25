#!/bin/bash

# ==========================================
# Rofi 音乐控制台触发脚本
# ==========================================

# 1. 抓取音乐状态与截断超长歌名 (最大 50 个字符)
STATUS=$(playerctl status 2>/dev/null)

if [ -z "$STATUS" ]; then
    SONG_INFO="No Music Playing"
    PLAY_PAUSE="󰐊 Play"
else
    SONG_INFO=$(playerctl metadata --format '{{ artist }} - {{ title }}' 2>/dev/null | cut -c 1-50)
    
    if [ "$STATUS" = "Playing" ]; then
        PLAY_PAUSE="󰏤 Pause"
    else
        PLAY_PAUSE="󰐊 Play"
    fi
fi

# 2. 定义控制按钮
PREV="󰒮 Prev"
NEXT="󰒭 Next"
STOP="󰓛 Stop"

# 3. 呼出 Rofi 面板
# -selected-row 1 确保光标默认落在播放键上
SELECTED=$(echo -e "$PREV\n$PLAY_PAUSE\n$NEXT\n$STOP" | \
           rofi -dmenu -i -p "  $SONG_INFO" \
           -theme ~/.config/rofi/themes/musicmenu.rasi \
           -selected-row 1)

# 4. 执行对应操作
case "$SELECTED" in
    "$PREV")
        playerctl previous ;;
    "$PLAY_PAUSE")
        playerctl play-pause ;;
    "$NEXT")
        playerctl next ;;
    "$STOP")
        playerctl stop ;;
esac
