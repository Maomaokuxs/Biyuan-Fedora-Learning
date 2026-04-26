#!/bin/bash
# 文件位置: ./install.sh

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SCRIPTS_DIR="$REPO_DIR/scripts"
export DOTFILES_DIR="$REPO_DIR/dotfiles"

# 色彩定义
CYAN='\033[0;36m'; BLUE='\033[0;34m'; GREEN='\033[0;32m'; PURPLE='\033[0;35m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "    ____  _                             "
    echo "   / __ )(_)__  __ __  ______ _____     "
    echo "  / __  / / / / / / / / / __ \`/ __ \    "
    echo " / /_/ / / /_/ / /_/ / / /_/ / / / /    "
    echo "/_____/_/\__, /\__,_/\__,_/_/ /_/       "
    echo "        /____/  ${PURPLE}Fedora Learning Engine${NC}"
    echo -e "${CYAN}------------------------------------------------------${NC}"
    echo -e "  ⚡ 模块化极速部署 | 兼容: GNOME / KDE / Niri | 📅 2026"
    echo -e "${CYAN}------------------------------------------------------${NC}\n"
}

source_modules() {
    for script in "$SCRIPTS_DIR"/*.sh; do
        [ -f "$script" ] && source "$script"
    done
}

main() {
    show_banner
    source_modules

    echo -e "${BLUE}[1/2]${NC} ${BOLD}🛡️  Security & Backup Layer${NC}"
    command -v setup_snapper_and_backup &> /dev/null && setup_snapper_and_backup
    echo ""

    echo -e "${BLUE}[2/2]${NC} ${BOLD}🔮 Desktop Experience & Drivers${NC}"
    echo "请选择要部署的桌面环境 (系统更新与显卡驱动将自动包含):"
    echo "  1) 🐧 GNOME (官方默认)"
    echo "  2) 🐉 KDE Plasma"
    echo "  3) 🪟 Niri (Wayland 平铺 + 自定义配置部署)"
    echo "  0) 跳过"
    read -p "选择 [0-3]: " de_choice

    case "$de_choice" in
        1) command -v install_desktop_gnome &> /dev/null && install_desktop_gnome ;;
        2) command -v install_desktop_kde &> /dev/null && install_desktop_kde ;;
        3) command -v install_desktop_niri &> /dev/null && install_desktop_niri ;;
        0|*) echo "跳过桌面安装。" ;;
    esac

    echo -e "\n${CYAN}------------------------------------------------------${NC}"
    echo -e "${GREEN}${BOLD}✨ 部署任务圆满完成！建议重启系统。${NC}"
    echo -e "${CYAN}------------------------------------------------------${NC}"
}

main "$@"