#!/bin/bash
# lyric-guard.sh — lyric.py 的前置守卫：无播放器时直接回 hidden，
# 省掉一次 python 启动（约几十 ms，每 2s 一次），有播放器时行为与原来完全一致。
playerctl status >/dev/null 2>&1 || { echo '{"text":"","class":"hidden"}'; exit 0; }
exec python3 "$(dirname "$(readlink -f "$0")")/common/lyric.py"
