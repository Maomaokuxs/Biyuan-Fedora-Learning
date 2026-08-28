#!/bin/bash
# 右键切换歌词显示
if [ -f /tmp/lyric_off ]; then
    rm -f /tmp/lyric_off
    notify-send -t 1000 "歌词" "已开启"
else
    touch /tmp/lyric_off
    notify-send -t 1000 "歌词" "已关闭"
fi
