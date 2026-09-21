#!/bin/bash
# brightness.sh — 把 waybar brightness.sh 的 {"percentage":N} 转成 ScriptPill 要的 {"text":...}
out=$(~/.config/waybar/scripts/brightness.sh 2>/dev/null)
p=$(printf '%s' "$out" | grep -o '[0-9]\+' | head -1)
[ -z "$p" ] && p=50
if [ "$p" -lt 34 ]; then icon="󰃞"; elif [ "$p" -lt 67 ]; then icon="󰃟"; else icon="󰃠"; fi
printf '{"text":"%s %s%%"}' "$icon" "$p"
