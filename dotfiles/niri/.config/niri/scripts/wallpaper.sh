#!/bin/bash

# ==========================================
# 随机壁纸挑选器 (对齐通知格式 & 优化随机性)
# ==========================================

# 1. 路径与配置
WALL_DIR="$HOME/Pictures/wallpapers"
SYNC_SCRIPT="$HOME/.config/niri/scripts/theme-sync.sh"

# 2. 扫描文件夹并建立数组 (增强随机性的核心)
shopt -s nullglob
walls=("$WALL_DIR"/*.{jpg,jpeg,png,webp})
shopt -u nullglob

# 安全校验
if [ ${#walls[@]} -eq 0 ]; then
    notify-send "随机壁纸失败" "在 $WALL_DIR 中没有找到图片！" -u critical
    exit 1
fi

# 3. 执行随机挑选
# 使用数组索引进行真正的随机分布
FULL_PATH="${walls[RANDOM % ${#walls[@]}]}"
SELECTED=$(basename "$FULL_PATH")

# 4. 发送通知 (精确匹配你要求的格式)
# -i "$FULL_PATH" 会让 Mako 在通知框显示该壁纸预览
notify-send "主题已同步" "壁纸已更换为: $SELECTED" -i "$FULL_PATH"

# 5. 调用中央大脑进行全系统变色
if [ -f "$SYNC_SCRIPT" ]; then
    bash "$SYNC_SCRIPT" "$FULL_PATH"
else
    notify-send "脚本错误" "找不到同步引擎: $SYNC_SCRIPT" -u critical
fi
