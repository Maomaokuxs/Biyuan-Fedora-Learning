#!/bin/bash
# 文件位置: ./install.sh

# 色彩定义 (提前定义确保自更新逻辑也能使用)
CYAN='\033[0;36m'; BLUE='\033[0;34m'; GREEN='\033[0;32m'; PURPLE='\033[0;35m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

# --- 0. 自动更新模块 ---
update_self() {
    if [ -d ".git" ] && command -v git &> /dev/null; then
        echo -e "${BLUE}>> 正在检查远程仓库更新...${NC}"
        git fetch --quiet
        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse @{u})

        if [ "$LOCAL" != "$REMOTE" ]; then
            if git pull; then
                echo -e "${GREEN}✅ 仓库代码已更新。${NC}"
                sync && sleep 0.5 
                exec bash "$0" --no-update "$@"
                exit 0
            fi
        fi
    fi
}

# --- 主程序入口 ---
main() {
    if [[ "$1" != "--no-update" ]]; then
        update_self "$@"
    else
        shift
    fi

    # 路径定义
    REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    SCRIPTS_DIR="$REPO_DIR/scripts"
    export DOTFILES_DIR="$REPO_DIR/dotfiles"
    export REPO_DIR  # 导出变量确保子脚本可见

    # 预热 sudo 权限，防止后续静默安装失败
    sudo -v || exit 1

    clear
    echo -e "${CYAN}${BOLD}"
    echo "    ____  _                             "
    echo "   / __ )(_)__  __ __  ______ _____     "
    echo "  / __  / / / / / / / / / __ \`/ __ \    "
    echo " / /_/ / / /_/ / /_/ / / /_/ / / / /    "
    echo "/_____/_/\__, /\__,_/\__,_/_/ /_/       "
    echo "        /____/  ${PURPLE}Fedora Learning Engine${NC}"
    echo -e "${CYAN}------------------------------------------------------${NC}"
    echo -e "  ⚡ 极速部署 | 自动同步远程 | 📅 2026"
    echo -e "${CYAN}------------------------------------------------------${NC}\n"

    # 加载模块
    if [ -d "$SCRIPTS_DIR" ]; then
        for script in "$SCRIPTS_DIR"/*.sh; do
            if [ -f "$script" ]; then
                chmod +x "$script"
                source "$script"
            fi
        done
    fi

    # --- 执行流程 ---
    
    # 1. 磁盘防护与备份
    if command -v setup_snapper_and_backup &> /dev/null; then
        setup_snapper_and_backup
    fi

    echo -e "\n${BLUE}>> Snapper 配置阶段结束，准备进入桌面部署...${NC}"

    # 2. 桌面环境部署选择菜单
    echo -e "\n${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 2] 桌面环境 (Desktop Environment) 选择${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo "  1) 🟢 GNOME 桌面环境 (官方标准)"
    echo "  2) 🔵 KDE Plasma 桌面环境 (高度定制)"
    echo "  3) 🟣 Niri 窗口管理器 (极简平铺)"
    echo "  0) ⏭️  跳过桌面部署 (仅保留基础环境)"
    read -p "请选择要部署的桌面环境 [0-3]: " desktop_opt

    case "$desktop_opt" in
        1)
            # 假设 06_desktop_gnome.sh 中的主函数名为 install_desktop_gnome
            if command -v install_desktop_gnome &> /dev/null; then
                install_desktop_gnome
            else
                echo -e "${RED}❌ 错误: 未找到 GNOME 部署模块或函数名不匹配。${NC}"
            fi
            ;;
        2)
            # 假设 05_desktop_kde.sh 中的主函数名为 install_desktop_kde
            if command -v install_desktop_kde &> /dev/null; then
                install_desktop_kde
            else
                echo -e "${RED}❌ 错误: 未找到 KDE 部署模块或函数名不匹配。${NC}"
            fi
            ;;
        3)
            if command -v install_desktop_niri &> /dev/null; then
                install_desktop_niri
            else
                echo -e "${RED}❌ 错误: 未找到 Niri 部署模块或函数名不匹配。${NC}"
            fi
            ;;
        0)
            echo -e "${YELLOW}>> 用户选择跳过桌面环境安装。${NC}"
            ;;
        *)
            echo -e "${RED}>> 无效输入，已跳过桌面环境安装。${NC}"
            ;;
    esac
    
    echo -e "\n${GREEN}✨ 系统部署流程全部结束！${NC}"
}

main "$@"