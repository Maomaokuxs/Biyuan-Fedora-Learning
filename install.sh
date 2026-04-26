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

    # 2. 桌面环境部署 (接力执行)
    if command -v install_desktop_niri &> /dev/null; then
        echo -e "${BLUE}>> Snapper 配置阶段结束，准备进入桌面部署...${NC}"
        install_desktop_niri
    fi
}

main "$@"