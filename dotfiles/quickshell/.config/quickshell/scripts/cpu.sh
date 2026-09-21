#!/bin/bash
# cpu.sh — 对齐 waybar custom/cpu（含 system_hidden 折叠语义）
if [ -f ~/.cache/by-mgr/waybar_system_hidden ]; then
  echo '{"text":"","class":"hidden"}'
else
  usage=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.0f", usage}')
  printf '{"text":"'$'\uf4bc'' %s%%"}' "$usage"
fi
