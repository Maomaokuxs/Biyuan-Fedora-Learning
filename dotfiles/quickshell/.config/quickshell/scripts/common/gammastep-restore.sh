#!/bin/bash
# 护眼模式持久化恢复：quickshell 启动时由 shell.qml 调一次（后台跑，不卡启动关键路径）。
# 状态文件 ~/.cache/by-mgr/gammastep-on 为准（last-write-wins）：1=恢复开启，0/缺失=不管。
# 开机时 Wayland 可能刚就绪，sleep 5 + pgrep 双保险；已开则不重复起。
sleep 5
STATE_FILE="$HOME/.cache/by-mgr/gammastep-on"
[ "$(cat "$STATE_FILE" 2>/dev/null)" = "1" ] || exit 0
pgrep -x gammastep >/dev/null && exit 0
command -v gammastep >/dev/null || exit 0
gammastep -O 4500 >/tmp/gammastep.log 2>&1 &
