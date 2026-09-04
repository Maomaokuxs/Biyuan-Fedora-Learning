#!/bin/bash

# 1. 获取更新列表
# dnf check-update 在有更新时返回 100，所以加上 || true 防止脚本意外退出
# dnf5 输出带 ANSI 颜色码：先剥离，再过滤汇总行（否则包行被转义符挡住、汇总行被误计）
# 通过 PackageKit(pkcon) 获取更新：普通用户即可见完整系统状态（与软件中心一致）。
# dnf5 check-update 在用户态元数据受限，仅能列出极少量包，不可用。
UPDATE_LIST=$(pkcon get-updates 2>/dev/null | grep -E "\([a-z0-9-]+\)$" | sed "s/^[^ ]* *//")
COUNT=$(echo "$UPDATE_LIST" | grep -vc "^$")

# 2. 判断内核更新
KERNEL_UPDATE=$(echo "$UPDATE_LIST" | grep -i "kernel")

# 3. 渲染逻辑：>50 才闪烁（many），其余 normal/kernel 不闪
if [ "$COUNT" -gt 50 ]; then
    TEXT="󰏖 $COUNT"
    ALT="many"
    TOOLTIP=$(printf "可用软件包更新（%s 个）：\n\n%s" "$COUNT" "$UPDATE_LIST")
elif [ "$COUNT" -gt 0 ]; then
    if [ -n "$KERNEL_UPDATE" ]; then
        TEXT=" $COUNT"
        ALT="kernel"
        TOOLTIP=$(printf "⚠ 重大更新提示：检测到新内核！\n\n%s" "$UPDATE_LIST")
    else
        TEXT="󰏖 $COUNT"
        ALT="normal"
        TOOLTIP=$(printf "可用软件包更新：\n\n%s" "$UPDATE_LIST")
    fi
else
    # 系统已是最新
    TEXT="󰏗 0" 
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