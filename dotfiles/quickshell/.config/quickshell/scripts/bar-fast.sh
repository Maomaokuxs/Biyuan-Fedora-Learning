#!/bin/bash
# bar-fast.sh — 共享快查聚合：2s 一次产出全部 2s 档 pill 数据。
# 单进程替代 13 个独立 ScriptPill 轮询（×双屏 = 26 个进程/2s），附带单相位更新
# （之前各 pill 独立计时，显隐逐个冒出来；现在同起同落）。
# 输出：{"rec":{...},"shot":{...},...}，每个值都是 {text,class} 结构。
# fcitx(1s)、外屏亮度(30s,ddc 慢)、weather/updates(慢) 不在内，各自保留。
# 本文件位置即基址（readlink 跟随 niri spawn 的工作目录变化），common 为同级 common/。
D="$(dirname "$(readlink -f "$0")")"
W="$D/common"

get() { local out; out=$("$@" 2>/dev/null); [ -z "$out" ] && out='{}'; printf '%s' "$out"; }
valid() { printf '%s' "$1" | jq -c . 2>/dev/null || echo '{}'; }
# 显隐 flag 同源输出（与文本同一相位，显隐动画单波齐出）
flag() { [ -f "$1" ] && echo 1 || echo 0; }

# 录制 pill：原 Bar.qml 内联 compound 语义保留（录制中合并 class=recording，且保证合法 JSON）
REC_A=$(get bash "$D/left-visibility.sh" F044A)
if [ -f /tmp/recording_status ]; then REC_B='{"class":"recording"}'; else REC_B='{}'; fi
REC=$(printf '%s\n%s' "$REC_A" "$REC_B" | jq -cs 'add // {}' 2>/dev/null || echo '{}')

jq -cn \
    --argjson rec "$REC" \
    --argjson shot "$(valid "$(get bash "$D/left-visibility.sh" F030)")" \
    --argjson pick "$(valid "$(get bash "$D/left-visibility.sh" F1FB)")" \
    --argjson clip "$(valid "$(get bash "$D/left-visibility.sh" F0EA)")" \
    --argjson gamma "$(valid "$(get bash "$W/gammastep.sh")")" \
    --argjson screen "$(valid "$(if [ -f ~/.cache/by-mgr/waybar_left_hidden ]; then echo '{"text":"","class":"hidden"}'; else bash "$W/screen.sh"; fi)")" \
    --argjson lyric "$(valid "$(get bash "$D/lyric-guard.sh")")" \
    --argjson bri "$(valid "$(get bash "$D/brightness.sh")")" \
    --argjson cpu "$(valid "$(get bash "$D/cpu.sh")")" \
    --argjson mem "$(valid "$(get bash "$D/memory.sh")")" \
    --argjson net "$(valid "$(get bash "$D/network.sh")")" \
    --argjson inhibit "$(valid "$(get bash "$D/inhibit.sh")")" \
    --argjson theme "$(valid "$(get bash "$W/auto-theme.sh")")" \
    --argjson pp "$(valid "$(get "$W/powerprofiles.sh")")" \
    --argjson flagL "$(flag ~/.cache/by-mgr/waybar_left_hidden)" \
    --argjson flagS "$(flag ~/.cache/by-mgr/waybar_system_hidden)" \
    --argjson flagM "$(flag ~/.cache/by-mgr/waybar_music_hidden)" \
    --argjson flagT "$(flag ~/.cache/by-mgr/qs_music_tail_hidden)" \
    '{rec:$rec,shot:$shot,pick:$pick,clip:$clip,gamma:$gamma,screen:$screen,lyric:$lyric,bri:$bri,cpu:$cpu,mem:$mem,net:$net,inhibit:$inhibit,theme:$theme,pp:$pp,flagL:$flagL,flagS:$flagS,flagM:$flagM,flagT:$flagT}'
