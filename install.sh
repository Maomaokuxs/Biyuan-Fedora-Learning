#!/bin/bash

# --- 全局环境变量与颜色 ---
export REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
export DOTFILES_DIR="$REPO_DIR/dotfiles"
export BACKUP_ROOT="$HOME/.dotfiles_backup"

export BLUE='\033[1;34m'
export GREEN='\033[1;32m'
export YELLOW='\033[1;33m'
export RED='\033[1;31m'
export NC='\033[0m'

# --- 1. 精准匹配你当前的物理文件名 (引入期) ---
source "$REPO_DIR/scripts/utils.sh"
source "$REPO_DIR/scripts/01_snapper_config.sh"
source "$REPO_DIR/scripts/02_base_env.sh"      # 完全对齐你的 02_base_env.sh
source "$REPO_DIR/scripts/03_gpu_drivers.sh"   # 完全对齐你的 03_gpu_drivers.sh
source "$REPO_DIR/scripts/04_desktop_niri.sh"
source "$REPO_DIR/scripts/05_desktop_kde.sh"
source "$REPO_DIR/scripts/06_desktop_gnome.sh"

# --- 2. 严格控制逻辑顺序 (执行期) ---
clear
print_header
sync_and_snapshot          # 云端同步与预检快照

setup_snapper              # 阶段 1：配置快照
setup_base                 # 阶段 2：基础环境与系统更新
setup_gpu                  # 阶段 3：显卡驱动硬件支持

# --- 3. 阶段 4：桌面环境路由选择 ---
echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN}  [系统阶段 4] 视觉交互：桌面环境选择${NC}"
echo -e "${BLUE}=====================================================${NC}"
while true; do
    echo "  1) Niri 桌面环境 (包含 Waybar, Rofi, Hypr-utils, Pywal 等)"
    echo "  2) KDE Plasma 桌面环境 (现代、强大)"
    echo "  3) GNOME 桌面环境 (Fedora 原生)"
    echo "  0) 结束并退出向导"
    
    read -p "请输入选项 [1-3, 0退出]: " dt_opt
    [[ "$dt_opt" == "0" ]] && break

    case $dt_opt in
        1) install_desktop_niri ;;
        2) install_desktop_kde ;;
        3) install_desktop_gnome ;;
        *) echo -e "${RED}无效选项${NC}" ;;
    esac
done

echo -e "\n${BLUE}✨ 部署任务全部完成！请重启系统以应用所有更改。${NC}\n"