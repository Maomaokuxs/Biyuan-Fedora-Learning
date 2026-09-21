#!/bin/bash
# dunst-count.sh — 通知未读数（栏无关：waybar custom / quickshell ScriptPill 通用）。
# dunst 接管后，history 条数即未读；点开历史后归零由 dunstctl history-pop 消费。
n=$(dunstctl count history 2>/dev/null | grep -o '[0-9]*' | head -1)
[ -z "$n" ] && n=0
if [ "$n" -gt 0 ]; then
  printf '{"text":"'$'\uf0f3'' %s","class":"unread","tooltip":"未读通知 %s 条（点击查看历史）"}' "$n" "$n"
else
  printf '{"text":"'$'\uf0f3''","class":"read","tooltip":"暂无未读通知"}'
fi
