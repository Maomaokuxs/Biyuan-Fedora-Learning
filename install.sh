#!/bin/bash

# --- 0. 基础配置 ---
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$REPO_DIR/dotfiles"
BACKUP_ROOT="$HOME/.dotfiles_backup"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- 1. 实心大标题 ---
if ! command -v figlet &> /dev/null; then sudo dnf install -y figlet &> /dev/null; fi
clear
echo -e "${BLUE}"
# 使用 block 字体实现实心效果
figlet -f block "BIYUAN"
figlet -f block "FEDORA"
echo -e "${NC}-----------------------------------------------------"
echo -e "       模块化环境引导程序 | 系统版本: 2026.04"
echo -e "-----------------------------------------------------\n"

# --- 2. 备份函数 ---
do_backup() {
    local name=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local bdir="$BACKUP_ROOT/${timestamp}_$name"
    mkdir -p "$bdir"
    
    if [ "$name" == "base" ]; then
        [ -f "$HOME/.bashrc" ] && cp "$HOME/.bashrc" "$bdir/"
    else
        [ -d "$HOME/.config/$name" ] && cp -rf "$HOME/.config/$name" "$bdir/"
    fi
    echo -e "${YELLOW}已备份 $name 旧配置至: $bdir${NC}"
}

# --- 3. 核心功能：精准 Stow ---
smart_stow() {
    local folder=$1
    cd "$DOTFILES_DIR"
    # 只 Stow 特定的文件夹，避免全量映射导致冗余
    stow -v -t ~ "$folder"
}

# --- 第一步：基本系统配置 ---
setup_base() {
    echo -e "${BLUE}[STEP 1] 正在配置基础系统环境...${NC}"
    read -p "是否同步 Bash 及基础工具配置? (含自动备份) [y/N] " confirm
    if [[ $confirm == [yY] ]]; then
        do_backup "base"
        # 假设仓库中基础配置放在 dotfiles/bash 目录下
        smart_stow "bash"
        sudo dnf install -y git curl fastfetch htop stow ImageMagick
        echo -e "${GREEN}基础环境配置完成。${NC}\n"
    fi
}

# --- 第二步：桌面环境选择 ---
setup_desktop() {
    echo -e "${BLUE}[STEP 2] 桌面环境与组件选择${NC}"
    echo "请选择要安装的组件 (输入数字):"
    options=("Niri 完整环境 (含 Waybar, Rofi, Lock/Idle)" "仅 Neovim 编辑器" "仅 Starship 提示符" "恢复备份" "退出")
    
    select opt in "${options[@]}"; do
        case $REPLY in
            1)
                echo -e "${YELLOW}正在安装 Niri 及其配套组件...${NC}"
                do_backup "niri"
                do_backup "waybar"
                do_backup "rofi"
                do_backup "hypr"
                
                # 安装软件
                sudo dnf install -y niri waybar rofi-wayland hypridle hyprlock python3-pywal
                
                # 精准映射对应的配置文件夹
                smart_stow "niri"
                smart_stow "waybar"
                smart_stow "rofi"
                smart_stow "hypr"
                echo -e "${GREEN}Niri 环境部署成功！${NC}"
                break
                ;;
            2)
                do_backup "nvim"
                sudo dnf install -y neovim
                smart_stow "nvim"
                break
                ;;
            3)
                do_backup "starship"
                sudo dnf install -y starship
                smart_stow "starship"
                break
                ;;
            4)
                echo "请手动进入 $BACKUP_ROOT 目录恢复所需文件。"
                break
                ;;
            5) exit 0 ;;
            *) echo "无效选项" ;;
        esac
    done
}

# --- 执行流程 ---
setup_base
setup_desktop

echo -e "\n${BLUE}✨ Biyuan Fedora 环境初始化流程结束！${NC}"