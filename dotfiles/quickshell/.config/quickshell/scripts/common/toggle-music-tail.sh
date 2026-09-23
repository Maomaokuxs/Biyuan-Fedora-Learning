#!/bin/bash
# toggle-music-tail.sh — 音律条右键：只藏排在它后面的跟随者（播放键/歌词），
# 自己和歌名留守当开关。quickshell 自有旗，不影响 waybar。
# 总闸（waybar_music_hidden，含音律）由歌名/歌词右键翻，见 toggle-music.sh。
FLAG="$HOME/.cache/by-mgr/qs_music_tail_hidden"
if [ -f "$FLAG" ]; then
    rm -f "$FLAG"
else
    touch "$FLAG"
fi
