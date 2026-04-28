#!/bin/bash

# 1. 获取更新列表并清理
# 使用 --quiet 模式，只保留包名
UPDATE_LIST=$(dnf check-update --quiet | grep '^[a-zA-Z0-9]' | tr -d '\0')
COUNT=$(echo "$UPDATE_LIST" | grep -vc '^$')

# 2. 判断内核更新
KERNEL_UPDATE=$(echo "$UPDATE_LIST" | grep -i "kernel")

# 3. 准备变量
if [ "$COUNT" -gt 0 ]; then
    if [ -n "$KERNEL_UPDATE" ]; then
        TEXT="󰔄 $COUNT"
        ALT="kernel"
        TOOLTIP=$(printf "重大更新提示 (内核)：\n%s" "$UPDATE_LIST")
    else
        TEXT="󰏖 $COUNT"
        ALT="normal"
        TOOLTIP=$(printf "可用软件包更新：\n%s" "$UPDATE_LIST")
    fi
else
    # 平时只显示一个合适的图标，不显示文字
    TEXT="📦0" 
    ALT="uptodate"
    TOOLTIP="系统已是最新状态"
fi

# 4. 使用 jq 导出
CLEAN_TOOLTIP=$(echo "$TOOLTIP" | tr -d '\0' | sed 's/\x1b\[[0-9;]*m//g')

jq -cn \
    --arg text "$TEXT" \
    --arg alt "$ALT" \
    --arg tooltip "$CLEAN_TOOLTIP" \
    --arg class "$ALT" \
    '{text: $text, alt: $alt, tooltip: $tooltip, class: $class}'
