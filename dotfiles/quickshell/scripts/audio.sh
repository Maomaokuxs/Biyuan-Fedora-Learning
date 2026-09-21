#!/bin/bash
# audio.sh — pulseaudio 对齐 waybar pulseaudio 模块 {icon} {volume}%
muted=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -qi yes && echo yes || echo no)
vol=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -Po '\d+(?=%)' | head -1)
[ -z "$vol" ] && vol=0
if [ "$muted" = yes ]; then
  echo '{"text":"'$'\U000F075F'' Muted"}'
else
  if [ "$vol" -eq 0 ]; then icon=$'\uf026'; elif [ "$vol" -lt 60 ]; then icon=$'\uf027'; else icon=$'\uf028'; fi
  printf '{"text":"%s %s%%"}' "$icon" "$vol"
fi
