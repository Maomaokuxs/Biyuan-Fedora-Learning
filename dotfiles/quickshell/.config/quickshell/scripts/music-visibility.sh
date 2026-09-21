#!/bin/bash
# music-visibility.sh — mprev/mplay/mnext 显隐（cava 左键切换）
# 用法: music-visibility.sh <mode>；mode: prev|play|next
if [ -f ~/.cache/by-mgr/waybar_music_hidden ]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi
case "$1" in
  prev) echo '{"text":"'$'\uf048''"}' ;;
  play)
    if playerctl status 2>/dev/null | grep -q Playing; then echo '{"text":"'$'\uf04c''"}'; else echo '{"text":"'$'\uf04b''"}'; fi ;;
  next) echo '{"text":"'$'\uf051''"}' ;;
esac
