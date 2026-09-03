#!/bin/bash
# 右键切换歌词显示
if [ -f $HOME/.cache/by-mgr/lyric_off ]; then
    rm -f $HOME/.cache/by-mgr/lyric_off
    notify-send -t 1000 "歌词" "已开启"
else
    touch $HOME/.cache/by-mgr/lyric_off
    notify-send -t 1000 "歌词" "已关闭"
fi
