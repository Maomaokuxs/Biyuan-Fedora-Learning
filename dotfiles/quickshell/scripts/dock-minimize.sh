#!/bin/bash
# 最小化窗口到 dock 收纳区：dock-minimize.sh <window-id>
# 用法：选中 dock 图标上已聚焦的窗口后调用；或绑 niri 快捷键传 focused id。
ID="$1"
[ -z "$ID" ] && { echo "usage: $0 <window-id>" >&2; exit 1; }
DIR="$(dirname "$(readlink -f "$0")")"
bash "$DIR/dock-ensure-stash.sh"
niri msg action move-window-to-workspace --window-id "$ID" --focus false "__dockmin__"
