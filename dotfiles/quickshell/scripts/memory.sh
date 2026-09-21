#!/bin/bash
# memory.sh — 对齐 waybar custom/memory
if [ -f ~/.cache/by-mgr/waybar_system_hidden ]; then
  echo '{"text":"","class":"hidden"}'
else
  used=$(free -m | awk '/Mem:/{print $3}'); total=$(free -m | awk '/Mem:/{print $2}')
  printf '{"text":"'$'\uefc5'' %.1fG","tooltip":"内存已用: %dMiB / %dMiB"}' "$(awk "BEGIN{print $used/1024}")" "$used" "$total"
fi
