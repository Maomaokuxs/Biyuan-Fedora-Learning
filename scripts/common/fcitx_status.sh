#!/bin/bash

# 获取当前输入法名称
STATUS=$(fcitx5-remote -n)

# 中/EN 文字方案
if [[ "$STATUS" == "keyboard-us" ]]; then
    echo "EN"
else
    echo "中"
fi
