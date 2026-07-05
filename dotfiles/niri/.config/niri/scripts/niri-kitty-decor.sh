#!/bin/bash
echo 'hide_window_decorations yes' > /tmp/kitty-decor.conf
trap 'rm -f /tmp/kitty-decor.conf' EXIT
# 保持进程存活直到 niri 退出
sleep infinity &
wait
