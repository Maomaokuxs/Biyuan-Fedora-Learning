#!/bin/bash

# 获取当前输入法名称
STATUS=$(fcitx5-remote -n)

# 图标映射逻辑
# 󰗊 代表中文/全球化，󰌌 代表英文字符/键盘
if [[ "$STATUS" == "rime" ]]; then
    echo "󰗊 Rime"  # 或者是 "󰗊 " (纯图标)
elif [[ "$STATUS" == "keyboard-us" ]]; then
    echo "󰌌 "
else
    echo "󰗊 "
fi
