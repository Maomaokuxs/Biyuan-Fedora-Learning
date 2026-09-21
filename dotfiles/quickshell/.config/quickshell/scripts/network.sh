#!/bin/bash
# network.sh — 对齐 waybar custom/network（图标占位，详情走 nmtui）
if [ -f ~/.cache/by-mgr/waybar_system_hidden ]; then
  echo '{"text":"","class":"hidden"}'
else
  echo '{"text":"'$'\U000f0928''","tooltip":"Network"}'
fi
