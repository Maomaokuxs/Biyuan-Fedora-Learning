#!/bin/bash
# 文件位置: dotfiles/niri/.config/niri/scripts/init-wallpaper.sh

# --- 1. 动态获取仓库根目录 ---
# 获取当前脚本的绝对路径
SCRIPT_PATH=$(readlink -f "$0")
# 根据你的目录结构 (dotfiles/niri/.config/niri/scripts/init-wallpaper.sh)，
# 仓库根目录在脚本位置的向上第 5 级
REPO_ROOT=$(dirname $(dirname $(dirname $(dirname $(dirname "$SCRIPT_PATH")))))

# --- 2. 定义路径变量 (基于动态根目录) ---
# 默认壁纸源文件
DEFAULT_WALL_SRC="$REPO_ROOT/assets/default_wallpaper.png"
# 壁纸库源文件夹
WALL_SRC_DIR="$REPO_ROOT/dotfiles/niri/wallpapers"

# 目标位置 (家目录下的标准图片路径)
WALL_DEST_DIR="$HOME/Pictures/Wallpapers"

echo -e ">> 检测到仓库根目录: $REPO_ROOT"

# --- 3. 检查并创建目标文件夹 ---
if [ ! -d "$WALL_DEST_DIR" ]; then
    echo ">> 正在创建壁纸目录: $WALL_DEST_DIR"
    mkdir -p "$WALL_DEST_DIR"
fi

# --- 4. 智能同步逻辑 ---

# A. 首先确保默认壁纸存在并复制
if [ -f "$DEFAULT_WALL_SRC" ]; then
    echo ">> 正在部署默认壁纸..."
    cp -n "$DEFAULT_WALL_SRC" "$WALL_DEST_DIR/default_wallpaper.png"
fi

# B. 增量同步壁纸库
if [ -d "$WALL_SRC_DIR" ]; then
    echo ">> 正在同步壁纸库资源..."
    # 使用 -n (no-clobber) 确保不覆盖用户已有的同名壁纸
    cp -rn "$WALL_SRC_DIR/." "$WALL_DEST_DIR/"
fi

# --- 5. 执行壁纸应用命令 ---
# 这里调用你习惯使用的壁纸后端，例如 swww 或 waypaper
# 示例：使用默认壁纸启动
if command -v swww &> /dev/null; then
    swww img "$WALL_DEST_DIR/default_wallpaper.png"
fi

echo "✅ 壁纸初始化完成。"