#!/bin/bash
# 文件位置: dotfiles/niri/.config/niri/scripts/init-wallpaper.sh

# 说明

# 第一部分用于动态的找到仓库的位置，还加入了兜底机制，指定了一个文件夹，但不一定会在这个地方，还是靠前面的推断位置

# 第二部分定义各种路径变量，默认壁纸位置，取色脚本位置，壁纸文件夹，
# 缓存文件夹（用于初始化脚本只在第一次安装时使用，他会在.cache/by-mgr生成一个空的锁文件）

# 第三部分用于 debug 报错

# 第四部分用于将壁纸移动至指定文件夹$HOME/Pictures/wallpapers

# 第五部分使用取色脚本初始化桌面

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

# --- 2. 核心路径定义 (支持多壁纸目录结构) ---
# 【架构升级】：指定仓库里的壁纸目录和默认壁纸名称
SOURCE_WALL_DIR="$REPO_ROOT/assets/wallpapers"
DEFAULT_WALL_NAME="default_wallpaper.jpg"

THEME_SYNC_SCRIPT="$REPO_ROOT/dotfiles/niri/.config/niri/scripts/theme-sync.sh"
# 如果 dotfiles 里找不到，尝试去仓库根目录 scripts 找 (增加兼容性)
[ -f "$THEME_SYNC_SCRIPT" ] || THEME_SYNC_SCRIPT="$REPO_ROOT/scripts/theme-sync.sh"

WALL_DEST_DIR="$HOME/Pictures/wallpapers"
mkdir -p "$WALL_DEST_DIR"

# 最终传递给引擎的默认壁纸路径
FINAL_WALLPAPER="$WALL_DEST_DIR/$DEFAULT_WALL_NAME"

# 【极简拦截逻辑】：定义缓存并进行存在性检查
CACHE_DIR="$HOME/.cache/by-mgr"
INIT_LOCK="$CACHE_DIR/wallpaper_init.lock"
mkdir -p "$CACHE_DIR"

# 如果发现锁文件，直接终止整个脚本，不执行任何后续操作！
if [ -f "$INIT_LOCK" ]; then
    echo -e "\033[0;34mℹ️  检测到缓存文件 $INIT_LOCK，初始化流程已跳过，脚本安全退出。\033[0m"
    exit 0
fi

# --- 3. 调试输出 ---
echo ">> Debug Info:"
echo "   Real REPO_ROOT: $REPO_ROOT"
echo "   Source Wallpapers: $SOURCE_WALL_DIR"
echo "   Target Engine: $THEME_SYNC_SCRIPT"

# --- 4. 导入全量壁纸与锁定默认项 ---
echo ">> 正在同步仓库壁纸库..."

# A. 全量导入：将仓库 assets/wallpapers 下的所有图片软链接到系统的图片目录
if [ -d "$SOURCE_WALL_DIR" ] && [ "$(ls -A "$SOURCE_WALL_DIR")" ]; then
    # 使用 -s 创建软链接，-f 强制覆盖同名链接，保护 SSD 且不占双份空间
    ln -sf "$SOURCE_WALL_DIR"/* "$WALL_DEST_DIR/"
    echo -e "\033[0;32m✅ 成功将壁纸资产库链接至: $WALL_DEST_DIR\033[0m"
else
    echo -e "\033[0;33m⚠️  Warning: 资产目录不存在或为空: $SOURCE_WALL_DIR\033[0m"
fi

# B. 默认壁纸仲裁逻辑
echo ">> Checking default wallpaper asset..."
if [ -f "$FINAL_WALLPAPER" ]; then
    # 如果目标目录成功拿到了默认壁纸（通过刚才的软链接）
    echo -e "\033[0;32m✅ 锁定默认壁纸: $FINAL_WALLPAPER\033[0m"
    
else
    echo -e "\033[0;31m❌ Error: 未找到指定的默认壁纸 ($DEFAULT_WALL_NAME)\033[0m"
    
    # 兜底求生逻辑：在刚才导入的壁纸中随便抓一张作为默认
    FINAL_WALLPAPER=$(ls "$WALL_DEST_DIR"/*.{png,jpg,jpeg,webp} 2>/dev/null | head -n 1)
    
    if [ -z "$FINAL_WALLPAPER" ]; then
        echo -e "\033[0;31m❌ Fatal: No wallpaper file available at all.\033[0m"
        exit 1
    fi
    echo -e "\033[0;33m⚠️  Fallback: 随机提取一张壁纸作为兜底: $FINAL_WALLPAPER\033[0m"
fi

# --- 5. 激活视觉引擎 ---
if [ -f "$THEME_SYNC_SCRIPT" ]; then
    echo ">> Found visual engine: $THEME_SYNC_SCRIPT"
    chmod +x "$THEME_SYNC_SCRIPT"
    # 使用 bash 调用确保稳定性
    bash "$THEME_SYNC_SCRIPT" "$FINAL_WALLPAPER"
    # 主题同步成功后创建锁文件，确保下次不再重复执行
    touch "$INIT_LOCK"
    echo -e "\033[0;32m✅ Initialization lock created: $INIT_LOCK\033[0m"
    else
        echo -e "\033[0;31m⚠️  Error: Cannot locate engine at $THEME_SYNC_SCRIPT\033[0m"
        
        # 最后的保命逻辑：尝试从当前已安装的配置目录查找
        ALT_SYNC="$HOME/.config/niri/scripts/theme-sync.sh"
        if [ -f "$ALT_SYNC" ]; then
            bash "$ALT_SYNC" "$FINAL_WALLPAPER"
        else
            if [ -n "$WAYLAND_DISPLAY" ]; then
                awww query &>/dev/null || awww init &>/dev/null
                awww img "$FINAL_WALLPAPER" --transition-type center
            fi
        fi
    fi
else
    echo -e "\033[0;31m❌ Fatal: No wallpaper file available at all. Engine aborted.\033[0m"
fi

echo "✨ Visualization system initialization finished."
