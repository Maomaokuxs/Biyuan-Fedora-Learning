#!/bin/bash
# left-visibility.sh — 左侧工具组显隐（recorder/screenshot/picker/clipboard/gammastep/theme）
# 用法: left-visibility.sh <codepoint-hex>  (如 F030)；hidden 时折叠，否则输出对应字形
code="$1"
if [ -f ~/.cache/by-mgr/waybar_left_hidden ]; then
  echo '{"text":"","class":"hidden"}'
else
  n=$((16#$code))
  if [ "$n" -gt 65535 ]; then
    glyph=$(printf "\U$(printf '%08X' "$n")")
  else
    glyph=$(printf "\u$(printf '%04X' "$n")")
  fi
  printf '{"text":"%s"}' "$glyph"
fi
