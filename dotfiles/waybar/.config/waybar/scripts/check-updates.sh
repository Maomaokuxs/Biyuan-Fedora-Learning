#!/bin/bash

# 1. 获取更新列表
# dnf check-update 在有更新时返回 100，所以加上 || true 防止脚本意外退出
UPDATE_LIST=$(dnf check-update --quiet 2>/dev/null | grep '^[a-zA-Z0-9]' | tr -d '\0')
COUNT=$(echo "$UPDATE_LIST" | grep -vc '^$')

# 2. 判断内核更新
KERNEL_UPDATE=$(echo "$UPDATE_LIST" | grep -i "kernel")

# 3. 渲染逻辑
if [ "$COUNT" -gt 0 ]; then
    if [ -n "$KERNEL_UPDATE" ]; then
        # 【修改点】：仅保留企鹅图标 
        TEXT=" $COUNT"
        ALT="kernel"
        TOOLTIP=$(printf "🚨 重大更新提示：检测到新内核！\n\n%s" "$UPDATE_LIST")
    else
        # 普通更新使用 󰏖 (Package)
        TEXT="󰏖 $COUNT"
        ALT="normal"
        TOOLTIP=$(printf "可用软件包更新：\n\n%s" "$UPDATE_LIST")
    fi
else
    # 系统已是最新
    TEXT="󰏗" 
    ALT="uptodate"
    TOOLTIP="系统已是最新状态"
fi

# 4. 导出为 JSON (Waybar 格式)
CLEAN_TOOLTIP=$(echo "$TOOLTIP" | tr -d '\0' | sed 's/\x1b\[[0-9;]*m//g')

jq -cn \
    --arg text "$TEXT" \
    --arg alt "$ALT" \
    --arg tooltip "$CLEAN_TOOLTIP" \
    --arg class "$ALT" \
    '{text: $text, alt: $alt, tooltip: $tooltip, class: $class}'