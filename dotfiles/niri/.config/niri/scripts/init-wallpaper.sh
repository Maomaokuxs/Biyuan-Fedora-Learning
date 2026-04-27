#!/bin/bash
# 文件位置: dotfiles/niri/.config/niri/scripts/init-wallpaper.sh

# 1. 动态获取仓库根目录
SCRIPT_PATH=$(readlink -f "$0")
search_dir=$(dirname "$SCRIPT_PATH")
REPO_ROOT=""
while [[ "$search_dir" != "/" ]]; do
    if [[ -d "$search_dir/assets" ]] || [[ -d "$search_dir/.git" ]]; then
        REPO_ROOT="$search_dir"
        break
    fi
    search_dir=$(dirname "$search_dir")
done

# 2. 路径定义
DEFAULT_WALL_SRC="$REPO_ROOT/assets/default_wallpaper.png"
THEME_SYNC_SCRIPT="$REPO_ROOT/scripts/theme-sync.sh"
WALL_DEST_DIR="$HOME/Pictures/Wallpapers"
mkdir -p "$WALL_DEST_DIR"

# 3. 部署默认壁纸
FINAL_WALLPAPER="$WALL_DEST_DIR/default_wallpaper.png"
if [ -f "$DEFAULT_WALL_SRC" ]; then
    cp -n "$DEFAULT_WALL_SRC" "$FINAL_WALLPAPER"
fi

# 4. 激活视觉引擎
if [ -f "$THEME_SYNC_SCRIPT" ]; then
    echo ">> 发现取色引擎: $THEME_SYNC_SCRIPT"
    chmod +x "$THEME_SYNC_SCRIPT"
    bash "$THEME_SYNC_SCRIPT" "$FINAL_WALLPAPER"
else
    echo -e "\033[0;31m⚠️ 错误: 找不到 $THEME_SYNC_SCRIPT，尝试备选路径...\033[0m"
    # 备选：如果在仓库没找到，尝试在当前家目录配置中找
    ALT_SYNC="$HOME/.config/niri/scripts/theme-sync.sh"
    if [ -f "$ALT_SYNC" ]; then
        bash "$ALT_SYNC" "$FINAL_WALLPAPER"
    else
        # 【核心修复】：增加 Wayland 环境感知，防止在安装阶段 (TTY) 强行启动 swww 导致卡死
        if [ -n "$WAYLAND_DISPLAY" ]; then
            swww query &>/dev/null || swww init &>/dev/null
            swww img "$FINAL_WALLPAPER"
        else
            echo -e "\033[0;33mℹ️  当前非 Wayland 环境，仅部署文件，跳过壁纸渲染守护进程。\033[0m"
        fi
    fi
fi

echo "✨ 视觉系统初始化结束。"