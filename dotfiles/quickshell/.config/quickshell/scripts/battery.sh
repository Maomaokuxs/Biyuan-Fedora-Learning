#!/bin/bash
# battery.sh — 对齐 waybar battery 模块
base=/sys/class/power_supply/BAT0
[ -d "$base" ] || base=/sys/class/power_supply/BAT1
[ -d "$base" ] || { echo '{"text":""}'; exit 0; }
cap=$(cat "$base/capacity" 2>/dev/null || echo 0)
st=$(cat "$base/status" 2>/dev/null || echo Unknown)
if [ "$st" = Charging ]; then printf '{"text":"'$'\U000f1013'' %s%%"}' "$cap"; exit 0; fi
if [ "$cap" -ge 90 ]; then icon=$'\uf240'; elif [ "$cap" -ge 70 ]; then icon=$'\uf241'; elif [ "$cap" -ge 40 ]; then icon=$'\uf242'; elif [ "$cap" -ge 15 ]; then icon=$'\uf243'; else icon=$'\uf244'; fi
printf '{"text":"%s %s%%"}' "$icon" "$cap"
