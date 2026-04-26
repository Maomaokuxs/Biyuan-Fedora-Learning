#!/bin/bash

# --- 0. 最小化环境自愈 (核心新增) ---
echo "正在检查基础环境..."
# 检查并安装最起码的工具
for cmd in stow figlet git curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "检测到缺少 $cmd，正在尝试补充安装..."
        sudo dnf install -y $cmd &> /dev/null
    fi
done

# --- 1. 全局环境变量 ---
export REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
export DOTFILES_DIR="$REPO_DIR/dotfiles"
export BACKUP_ROOT="$HOME/.dotfiles_backup"

# 定义颜色 (防止某些环境不支持颜色导致的报错)
export BLUE='\033[1;34m'
export GREEN='\033[1;32m'
export YELLOW='\033[1;33m'
export RED='\033[1;31m'
export NC='\033[0m'

# --- 2. 加载模块 ---
source "$REPO_DIR/scripts/utils.sh"
source "$REPO_DIR/scripts/01_snapper_config.sh"
# ... 后续加载保持不变
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