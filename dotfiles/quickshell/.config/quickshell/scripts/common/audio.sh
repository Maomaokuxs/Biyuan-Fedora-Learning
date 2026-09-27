#!/bin/bash
# audio.sh — 默认输出设备音量（JSON，供 AudioPill / VolCard / ControlCenter）
# 输出: {"text":" <pct>%","class":"muted"|"","vol":0.40,"muted":0/1,"tooltip":"..."}
# Quickshell Pipewire 服务在 pipewire 1.6 下 sink 永不 ready，改走 wpctl。
out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || {
    echo '{"text":"","class":"","vol":0,"muted":0,"tooltip":"无音频设备"}'
    exit 0
}
vol=$(echo "$out" | awk '{print $2}')
muted=0
echo "$out" | grep -q "MUTED" && muted=1
pct=$(awk -v v="$vol" 'BEGIN{printf "%d", v*100}')
if [ "$muted" = 1 ]; then
    text="󰝟 Muted"; cls="muted"
elif [ "$pct" -eq 0 ]; then
    text=" 0%"; cls=""
elif [ "$pct" -lt 60 ]; then
    text=" $pct%"; cls=""
else
    text=" $pct%"; cls=""
fi
printf '{"text":"%s","class":"%s","vol":%s,"muted":%d,"tooltip":"音量 %s%%"}' \
    "$text" "$cls" "$vol" "$muted" "$pct"
