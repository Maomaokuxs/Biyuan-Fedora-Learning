#!/bin/bash

# --- 0. 基础配置与颜色定义 ---
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$REPO_DIR/dotfiles"
BACKUP_DIR="$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S)"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- 1. 弹出巨大文字标题 ---
if ! command -v figlet &> /dev/null; then sudo dnf install -y figlet &> /dev/null; fi
clear
echo -e "${BLUE}"
figlet -f slant "Biyuan Fedora"
echo -e "${NC}-----------------------------------------------------"
echo -e "       Biyuan 环境管理系统 (同步/备份/安装)"
echo -e "-----------------------------------------------------\n"

# --- 2. 远程版本检测功能 ---
check_update() {
    echo -e "${BLUE}[1/4] 检查远程仓库更新...${NC}"
    git fetch origin main -q
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse @{u})

    if [ "$LOCAL" != "$REMOTE" ]; then
        echo -e "${YELLOW}检测到远程有新版本！${NC}"
        read -p "是否更新本地代码并重新部署配置? [y/N] " confirm
        if [[ $confirm == [yY] ]]; then
            git pull origin main
            return 0 # 需要重新部署
        fi
    else
        echo -e "${GREEN}本地代码已是最新版本。${NC}"
    fi
    return 1 # 不需要更新或用户拒绝
}

# --- 3. 备份功能 ---
backup_configs() {
    echo -e "${BLUE}[2/4] 正在备份当前旧配置至 $BACKUP_DIR...${NC}"
    mkdir -p "$BACKUP_DIR"
    # 仅备份 Stow 涉及的真实文件/文件夹
    for item in $(ls -A "$DOTFILES_DIR/.config" 2>/dev/null); do
        if [ -e "$HOME/.config/$item" ]; then
            cp -rf "$HOME/.config/$item" "$BACKUP_DIR/"
        fi
    done
    if [ -f "$HOME/.bashrc" ]; then cp "$HOME/.bashrc" "$BACKUP_DIR/"; fi
    echo -e "${GREEN}备份完成。${NC}"
}

# --- 4. 恢复功能 ---
restore_configs() {
    LAST_BACKUP=$(ls -td $HOME/.dotfiles_backup/* 2>/dev/null | head -1)
    if [ -z "$LAST_BACKUP" ]; then
        echo -e "${RED}未找到任何备份记录！${NC}"
        return
    fi
    echo -e "${YELLOW}确定要从 $LAST_BACKUP 恢复配置吗?${NC}"
    read -p "此操作将覆盖当前配置 [y/N] " confirm
    if [[ $confirm == [yY] ]]; then
        cp -rf "$LAST_BACKUP/." "$HOME/"
        echo -e "${GREEN}恢复成功！${NC}"
    fi
}

# --- 5. 交互式安装逻辑 ---
install_menu() {
    echo -e "\n${BLUE}[3/4] 软件组件安装 (多选请用空格，直接回车跳过):${NC}"
    options=("基础工具 (git, curl, fastfetch)" "窗口管理器 (niri, hypridle, hyprlock)" "界面组件 (waybar, rofi-wayland)" "开发工具 (neovim, pywal)" "【恢复上一次备份】" "退出")
    
    select opt in "${options[@]}"; do
        case $REPLY in
            1) sudo dnf install -y git curl fastfetch htop ;;
            2) sudo dnf install -y niri hypridle hyprlock ;;
            3) sudo dnf install -y waybar rofi-wayland ;;
            4) sudo dnf install -y neovim python3-pywal ImageMagick ;;
            5) restore_configs ;;
            6) break ;;
            *) echo "无效选项，直接回车继续流程" ; break ;;
        esac
    done
}

# --- 执行主流程 ---
check_update
read -p "是否需要重新部署配置(Stow)? (会先自动备份) [y/N] " deploy_choice
if [[ $deploy_choice == [yY] ]]; then
    backup_configs
    cd "$DOTFILES_DIR"
    stow . -t ~ --adopt # --adopt 会处理潜在的冲突
    echo -e "${GREEN}配置已通过 Stow 关联完成。${NC}"
fi

install_menu

echo -e "\n${BLUE}=== 所有操作已完成 ===${NC}"