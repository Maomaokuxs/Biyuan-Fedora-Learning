#!/bin/bash

# 变量定义
CACHE_WALL="$HOME/.cache/current_wallpaper"
DEFAULT_WALL="$HOME/Pictures/wallpapers/default_initial_wallpaper.png"

# 逻辑判定
if [ -f "$CACHE_WALL" ]; then
    TARGET_WALL=$(cat "$CACHE_WALL")
    # 安全性检查：如果缓存的壁纸被删除了，回退到默认
    [ ! -f "$TARGET_WALL" ] && TARGET_WALL="$DEFAULT_WALL"
else
    TARGET_WALL="$DEFAULT_WALL"
fi

# 应用壁纸 (以 swww 为例)
if command -v swww-daemon &> /dev/null; then
    swww img "$TARGET_WALL" --transition-type simple
fi

# 触发色彩同步
if command -v hellwal &> /dev/null; then
    hellwal -i "$TARGET_WALL" > /dev/null 2>&1
fi