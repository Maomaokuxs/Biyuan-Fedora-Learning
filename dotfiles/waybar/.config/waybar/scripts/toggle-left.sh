#!/bin/bash
# toggle-left.sh — 切换左侧三功能模块显隐（recorder/screenshot/picker）
FLAG="/tmp/waybar_left_hidden"
if [ -f "$FLAG" ]; then
    rm -f "$FLAG"
else
    touch "$FLAG"
fi
