#!/bin/bash
# bluetooth.sh — 对齐 waybar custom/bluetooth
if [ -f ~/.cache/by-mgr/waybar_system_hidden ]; then
  echo '{"text":"","class":"hidden"}'
elif bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
  echo '{"text":"'$'\uf293''"}'
else
  echo '{"text":"'$'\U000f00b2''"}'
fi
