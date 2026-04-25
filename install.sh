#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

echo -e "${BLUE}=== Biyuan 的 Fedora 环境自动引导程序 ===${NC}"

# --- 第一步：同步配置 (Stow) ---
echo -e "\n${GREEN}[1/2] 正在建立配置文件关联 (Stow)...${NC}"
sudo dnf install -y stow # 确保 stow 存在
cd "$(dirname "$0")/dotfiles"
stow . -t ~
echo "✅ 配置文件已通过软链接映射完成。"

# --- 第二步：交互式安装软件 ---
echo -e "\n${GREEN}[2/2] 请选择需要安装的组件 (输入数字，多个请用空格隔开，直接回车结束):${NC}"

# 定义软件包组
options=("基础工具 (git, curl, fastfetch)" "窗口管理器 (niri, hypridle, hyprlock)" "界面组件 (waybar, rofi-wayland)" "开发工具 (neovim, python3-pywal)" "退出")

menu() {
    for i in "${!options[@]}"; do
        printf "%3d) %s\n" $((i+1)) "${options[i]}"
    done
}

menu
while true; do
    read -p "选择组件 [1-5]: " choice
    case $choice in
        1)
            echo "正在安装基础工具..."
            sudo dnf install -q -y git curl fastfetch htop
            ;;
        2)
            echo "正在安装 Niri 相关..."
            sudo dnf install -q -y niri hypridle hyprlock
            ;;
        3)
            echo "正在安装 Waybar & Rofi..."
            sudo dnf install -q -y waybar rofi-wayland
            ;;
        4)
            echo "正在安装开发工具..."
            sudo dnf install -q -y neovim python3-pywal ImageMagick
            ;;
        5|"")
            echo -e "${BLUE}安装流程结束。${NC}"
            break
            ;;
        *)
            echo "无效选项 $REPLY"
            ;;
    esac
done

echo -e "\n${BLUE}恭喜！环境部署完成。${NC}"