#!/bin/bash
# 文件位置: ./install.sh

# --- 0. 自动更新模块 (运行前执行) ---
update_self() {
    # 检查当前目录是否为 Git 仓库
    if [ -d ".git" ] && command -v git &> /dev/null; then
        echo -e "${BLUE}>> 正在检查远程仓库更新...${NC}"
        
        # 尝试获取远程状态
        git fetch --quiet
        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse @{u})
        BASE=$(git merge-base @ @{u})

        if [ "$LOCAL" = "$REMOTE" ]; then
            echo -e "${GREEN}✅ 当前已是最新版本。${NC}"
        elif [ "$LOCAL" = "$BASE" ]; then
            echo -e "${YELLOW}>> 发现新版本，正在自动同步...${NC}"
            if git pull; then
                echo -e "${GREEN}✅ 更新成功！正在重新启动脚本以应用更改...${NC}"
                exec bash "$0" "$@" # 关键：重新执行脚本本身
                exit 0
            else
                echo -e "${RED}❌ 自动更新失败，请检查网络或手动处理冲突。${NC}"
            fi
        else
            echo -e "${PURPLE}⚠️  本地有未推送的修改，跳过自动更新。${NC}"
        fi
    else
        echo -e "${YELLOW}>> 非 Git 运行环境，跳过自动更新检查。${NC}"
    fi
}

# --- 基础配置与路径 ---
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SCRIPTS_DIR="$REPO_DIR/scripts"
export DOTFILES_DIR="$REPO_DIR/dotfiles"

# 色彩定义
CYAN='\033[0;36m'; BLUE='\033[0;34m'; GREEN='\033[0;32m'; PURPLE='\033[0;35m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

# --- 主程序入口 ---
main() {
    # 1. 优先执行自更新 (仅在第一次运行且未带 --no-update 参数时执行)
    if [[ "$1" != "--no-update" ]]; then
        update_self "$@"
    fi

    # 2. 显示标题
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

    # 3. 加载后续模块 (scripts/*.sh)
    if [ -d "$SCRIPTS_DIR" ]; then
        for script in "$SCRIPTS_DIR"/*.sh; do
            [ -f "$script" ] && source "$script"
        done
    fi

    # 4. 执行后续流程
    setup_snapper_and_backup      # 磁盘防护模块
    install_desktop_niri          # 桌面部署模块 (内部已包含显卡驱动逻辑)
}

main "$@"