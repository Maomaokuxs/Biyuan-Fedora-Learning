#!/bin/bash
# 文件位置: dotfiles/niri/.config/niri/scripts/init-wallpaper.sh

# --- 1. 智能查找真正的仓库根目录 (Feature-Based Search) ---
REAL_PATH=$(readlink -f "$0")
CURRENT_LOOKUP=$(dirname "$REAL_PATH")
REPO_ROOT=""

# 向上递归查找包含 'install.sh' 的目录，确保定位到仓库根
while [[ "$CURRENT_LOOKUP" != "/" ]]; do
    if [[ -f "$CURRENT_LOOKUP/install.sh" ]]; then
        REPO_ROOT="$CURRENT_LOOKUP"
        break
    fi
    CURRENT_LOOKUP=$(dirname "$CURRENT_LOOKUP")
done

# 兜底指定
: "${REPO_ROOT:=$HOME/Documents/github/Biyuan-Fedora-Learning}"

# --- 2. 核心路径定义 (关键修正区) ---
# 壁纸资产在仓库根目录
DEFAULT_WALL_SRC="$REPO_ROOT/assets/default_wallpaper.jpg"

# 【核心修复】：根据你之前 find 的结果，脚本实际在 dotfiles 深度目录下
THEME_SYNC_SCRIPT="$REPO_ROOT/dotfiles/niri/.config/niri/scripts/theme-sync.sh"

# 如果 dotfiles 里找不到，尝试去仓库根目录 scripts 找 (增加兼容性)
[ -f "$THEME_SYNC_SCRIPT" ] || THEME_SYNC_SCRIPT="$REPO_ROOT/scripts/theme-sync.sh"

WALL_DEST_DIR="$HOME/Pictures/wallpapers"
mkdir -p "$WALL_DEST_DIR"
FINAL_WALLPAPER="$WALL_DEST_DIR/default_wallpaper.jpg"

# --- 3. 调试输出 ---
echo ">> Debug Info:"
echo "   Real REPO_ROOT: $REPO_ROOT"
echo "   Target Engine: $THEME_SYNC_SCRIPT"

# --- 4. 部署默认壁纸 (优化逻辑) ---
echo ">> Checking default wallpaper asset..."
if [ -f "$DEFAULT_WALL_SRC" ]; then
    # 【修复点】：使用软链接代替复制，防止目录充满重复物理文件
    # -s: 软链接, -f: 强制覆盖旧链接（确保仓库图片更新时能同步）
    ln -sf "$DEFAULT_WALL_SRC" "$FINAL_WALLPAPER"
    echo -e "\033[0;32m✅ Wallpaper linked: $FINAL_WALLPAPER -> $DEFAULT_WALL_SRC\033[0m"
else
    echo -e "\033[0;33m⚠️  Warning: Asset not found at $DEFAULT_WALL_SRC\033[0m"
    
    # 只有当链接失效且目标文件不存在时，才尝试寻找备份
    if [ ! -f "$FINAL_WALLPAPER" ]; then
        FINAL_WALLPAPER=$(ls "$WALL_DEST_DIR"/*.{png,jpg,jpeg} 2>/dev/null | grep -v "default_wallpaper.jpg" | head -n 1)
    fi
fi

# --- 5. 激活视觉引擎 ---
if [ -f "$FINAL_WALLPAPER" ]; then
    if [ -f "$THEME_SYNC_SCRIPT" ]; then
        echo ">> Found visual engine: $THEME_SYNC_SCRIPT"
        chmod +x "$THEME_SYNC_SCRIPT"
        # 使用 bash 调用确保稳定性
        bash "$THEME_SYNC_SCRIPT" "$FINAL_WALLPAPER"
    else
        echo -e "\033[0;31m⚠️  Error: Cannot locate engine at $THEME_SYNC_SCRIPT\033[0m"
        
        # 最后的保命逻辑：尝试从当前已安装的配置目录查找
        ALT_SYNC="$HOME/.config/niri/scripts/theme-sync.sh"
        if [ -f "$ALT_SYNC" ]; then
            bash "$ALT_SYNC" "$FINAL_WALLPAPER"
        else
            if [ -n "$WAYLAND_DISPLAY" ]; then
                swww query &>/dev/null || swww init &>/dev/null
                swww img "$FINAL_WALLPAPER" --transition-type center
            fi
        fi
    fi
else
    echo -e "\033[0;31m❌ Fatal: No wallpaper file available.\033[0m"
fi

echo "✨ Visualization system initialization finished."