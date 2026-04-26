#!/bin/bash

# --- 0. 最小化环境自愈 (确保基础工具存在) ---
echo "正在检查基础环境..."
MISSING_TOOLS=""
for cmd in stow figlet git curl; do
    if ! command -v $cmd &> /dev/null; then
        MISSING_TOOLS="$MISSING_TOOLS $cmd"
    fi
done

if [ -n "$MISSING_TOOLS" ]; then
    echo "检测到缺少基础工具: $MISSING_TOOLS，正在补充安装..."
    sudo dnf install -y $MISSING_TOOLS &> /dev/null
    echo "环境修复完成，正在重新加载..."
fi

# --- 1. 全局变量定义 ---
export REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
export DOTFILES_DIR="$REPO_DIR/dotfiles"
export BACKUP_ROOT="$HOME/.dotfiles_backup"

export BLUE='\033[1;34m'
export GREEN='\033[1;32m'
export YELLOW='\033[1;33m'
export RED='\033[1;31m'
export NC='\033[0m'

# --- 2. 核心函数加载 (必须在环境自检后) ---
source "$REPO_DIR/scripts/utils.sh"
source "$REPO_DIR/scripts/01_snapper_config.sh"
source "$REPO_DIR/scripts/02_base_env.sh"
source "$REPO_DIR/scripts/03_gpu_drivers.sh"
source "$REPO_DIR/scripts/04_desktop_niri.sh"
source "$REPO_DIR/scripts/05_desktop_kde.sh"
source "$REPO_DIR/scripts/06_desktop_gnome.sh"

# --- 3. 严格执行流 ---
clear
print_header
sync_and_snapshot   # 这里包含了云端更新检测

# 如果刚才触发了 git pull 导致的重启，exec 会从这里重新开始
setup_snapper       # 阶段 1
setup_base          # 阶段 2
setup_gpu           # 阶段 3

# --- 4. 阶段 4：桌面环境路由 ---
echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN}  [阶段 4] 视觉交互：桌面环境选择${NC}"
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

echo -e "\n${BLUE}✨ 部署任务全部完成！请重启系统。${NC}\n"