#!/bin/bash
# 文件位置: dotfiles/niri/.config/niri/scripts/init-wallpaper.sh

# --- 1. 动态获取仓库根目录 (更鲁棒的方案) ---
# 获取脚本所在的实际物理目录
CURRENT_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
REPO_ROOT="$CURRENT_BACKUP"

# 向上循环查找包含 .git 或 assets 的目录作为根目录
search_dir="$CURRENT_DIR"
while [[ "$search_dir" != "/" ]]; do
    if [[ -d "$search_dir/assets" ]] || [[ -d "$search_dir/.git" ]]; then
        REPO_ROOT="$search_dir"
        break
    fi
    search_dir=$(dirname "$search_dir")
done

if [[ -z "$REPO_ROOT" ]]; then
    echo -e "\033[0;31m❌ 错误: 无法定位仓库根目录！\033[0m"
    exit 1
fi

# --- 2. 定义路径变量 ---
DEFAULT_WALL_SRC="$REPO_ROOT/assets/default_wallpaper.png"
WALL_SRC_DIR="$REPO_ROOT/dotfiles/niri/wallpapers"
WALL_DEST_DIR="$HOME/Pictures/Wallpapers"

echo -e ">> 仓库根目录定位成功: \033[0;32m$REPO_ROOT\033[0m"

# --- 3. 检查并创建目标文件夹 ---
if [ ! -d "$WALL_DEST_DIR" ]; then
    echo ">> 正在创建壁纸目录: $WALL_DEST_DIR"
    mkdir -p "$WALL_DEST_DIR"
fi

# --- 4. 智能同步逻辑 (增加调试信息) ---

# A. 部署默认壁纸
if [ -f "$DEFAULT_WALL_SRC" ]; then
    echo ">> 正在部署默认壁纸..."
    cp -n "$DEFAULT_WALL_SRC" "$WALL_DEST_DIR/default_wallpaper.png"
else
    echo -e "\033[0;33m⚠️  未找到默认壁纸源文件: $DEFAULT_WALL_SRC\033[0m"
fi

# B. 增量同步壁纸库
if [ -d "$WALL_SRC_DIR" ]; then
    # 检查源目录是否为空
    if [ "$(ls -A "$WALL_SRC_DIR" 2>/dev/null)" ]; then
        echo ">> 正在同步壁纸库资源..."
        # 显式使用 ./* 确保复制内容
        cp -rn "$WALL_SRC_DIR"/. "$WALL_DEST_DIR/"
        echo -e "\033[0;32m✅ 壁纸同步成功。\033[0m"
    else
        echo -e "\033[0;33m⚠️  壁纸源目录为空: $WALL_SRC_DIR\033[0m"
    fi
else
    echo -e "\033[0;31m❌ 找不到壁纸源目录: $WALL_SRC_DIR\033[0m"
fi

# --- 5. 执行壁纸应用命令 ---
if command -v swww &> /dev/null; then
    # 确保 swww daemon 正在运行
    swww query &>/dev/null || swww init &>/dev/null
    sleep 0.5
    swww img "$WALL_DEST_DIR/default_wallpaper.png" --transition-type center
fi

echo "✨ 壁纸初始化任务结束。"