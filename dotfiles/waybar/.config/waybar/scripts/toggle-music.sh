#!/bin/bash
# toggle-music.sh — 切换 waybar 音乐控件显隐（由 cava 左键触发）
# 无需刷新 waybar：模块 interval 1s 轮询标记，1秒内自动显隐
FLAG="/tmp/waybar_music_hidden"
if [ -f "$FLAG" ]; then
    rm -f "$FLAG"
else
    touch "$FLAG"
fi
