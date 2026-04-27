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

# 2. 路径定义 (修复了大小写，统一使用小写 wallpapers)
DEFAULT_WALL_SRC="$REPO_ROOT/assets/default_wallpaper.png"
THEME_SYNC_SCRIPT="$REPO_ROOT/scripts/theme-sync.sh"
WALL_DEST_DIR="$HOME/Pictures/wallpapers"
mkdir -p "$WALL_DEST_DIR"

# 3. 部署默认壁纸
FINAL_WALLPAPER="$WALL_DEST_DIR/default_wallpaper.png"

echo ">> 正在检查默认壁纸资产..."
if [ -f "$DEFAULT_WALL_SRC" ]; then
    cp -n "$DEFAULT_WALL_SRC" "$FINAL_WALLPAPER"
    echo -e "\033[0;32m✅ 默认壁纸已就绪: $FINAL_WALLPAPER\033[0m"
else
    echo -e "\033[0;33m⚠️ 警告: 仓库中未找到初始壁纸 ($DEFAULT_WALL_SRC)。\033[0m"
fi

# 4. 激活视觉引擎
# 【核心修复】：必须确保 FINAL_WALLPAPER 真实存在，才能呼叫取色脚本！
if [ -f "$FINAL_WALLPAPER" ]; then
    if [ -f "$THEME_SYNC_SCRIPT" ]; then
        echo ">> 发现取色引擎: $THEME_SYNC_SCRIPT"
        chmod +x "$THEME_SYNC_SCRIPT"
        bash "$THEME_SYNC_SCRIPT" "$FINAL_WALLPAPER"
    else
        echo -e "\033[0;31m⚠️ 错误: 找不到 $THEME_SYNC_SCRIPT，尝试备选路径...\033[0m"
        ALT_SYNC="$HOME/.config/niri/scripts/theme-sync.sh"
        if [ -f "$ALT_SYNC" ]; then
            bash "$ALT_SYNC" "$FINAL_WALLPAPER"
        else
            if [ -n "$WAYLAND_DISPLAY" ]; then
                swww query &>/dev/null || swww init &>/dev/null
                swww img "$FINAL_WALLPAPER"
            else
                echo -e "\033[0;33mℹ️  当前非 Wayland 环境，跳过壁纸渲染守护进程。\033[0m"
            fi
        fi
    fi
else
    # 如果连壁纸文件都没有，果断阻断流程，防止产生僵尸配置
    echo -e "\033[0;31m❌ 致命错误: 目标壁纸文件不存在，已放弃呼叫取色引擎！请手动放置一张壁纸并运行 theme-sync.sh。\033[0m"
fi

echo "✨ 视觉系统初始化结束。"