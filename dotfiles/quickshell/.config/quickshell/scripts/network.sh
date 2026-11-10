#!/bin/bash
# network.sh — 网线优先：有线 connected → 网线图标；否则 WiFi connected → 按信号强度分档图标；否则断开图标
# 图标走 Nerd Font（与栏字体 JetBrainsMono Nerd Font 一致）；tooltip 显示活动连接名（WiFi 带信号%）。
# 判断按设备 TYPE，不写死接口名；tun/loopback/wifi-p2p 一律忽略。
if [ -f ~/.cache/by-mgr/waybar_system_hidden ]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

# 设备状态：nmcli -t -f DEVICE,TYPE,STATE device
#   eno1:ethernet:connected / wlp4s0:wifi:connected / tailscale0:tun:connected (externally) ...
devs=$(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null)

# 第一个已连接的有线 / WiFi 设备（按类型，不按接口名；"connected (externally)" 也算已连接）
eth_dev=$(printf '%s\n' "$devs" | awk -F: '$2=="ethernet" && $3 ~ /^connected/ {print $1; exit}')
wifi_dev=$(printf '%s\n' "$devs" | awk -F: '$2=="wifi" && $3 ~ /^connected/ {print $1; exit}')

# 活动连接名（tooltip 用；名含冒号也不怕，取第一个冒号之后全部）
conn_name() { nmcli -t -f GENERAL.CONNECTION device show "$1" 2>/dev/null | cut -d: -f2-; }

# Nerd Font 图标：U+F0200 md-ethernet / U+F0928~U+F091F md-wifi 4~1 格 / U+F092E md-wifi-off
if [ -n "$eth_dev" ]; then
  icon=$'\U000f0200'
  tip=$(conn_name "$eth_dev"); [ -z "$tip" ] && tip="有线连接"
elif [ -n "$wifi_dev" ]; then
  # 信号强度：读 nmcli 缓存（--rescan no，不触发扫描；2 秒一轮询反复扫网会卡），读不到回落满格
  sig=$(nmcli -t -f IN-USE,SIGNAL device wifi list ifname "$wifi_dev" --rescan no 2>/dev/null | awk -F: '$1=="*" {print $2; exit}')
  case "$sig" in ''|*[!0-9]*) sig="";; esac
  if [ -z "$sig" ] || [ "$sig" -ge 75 ]; then
    icon=$'\U000f0928'
  elif [ "$sig" -ge 50 ]; then
    icon=$'\U000f0925'
  elif [ "$sig" -ge 25 ]; then
    icon=$'\U000f0922'
  else
    icon=$'\U000f091f'
  fi
  tip=$(conn_name "$wifi_dev"); [ -z "$tip" ] && tip="Wi-Fi"
  [ -n "$sig" ] && tip="$tip $sig%"
else
  icon=$'\U000f092e'
  tip="未连接"
fi

jq -cn --arg text "$icon" --arg tooltip "$tip" '{text:$text, tooltip:$tooltip}'
