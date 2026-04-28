#!/bin/bash
# 文件位置: ./install.sh

# 色彩定义
CYAN='\033[0;36m'; BLUE='\033[0;34m'; GREEN='\033[0;32m'; PURPLE='\033[0;35m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

# --- 主程序入口 ---
main() {
    # 状态标记：检查是否是更新后重新拉起的脚本
    local is_resumed=false
    if [[ "$1" == "--resumed" ]]; then
        is_resumed=true
        shift
    fi

    # 路径定义
    REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    SCRIPTS_DIR="$REPO_DIR/scripts"
    export DOTFILES_DIR="$REPO_DIR/dotfiles"
    export REPO_DIR

    # 预热 sudo 权限
    sudo -v || exit 1

    # 如果是首次启动（非更新后重启），则显示欢迎画面
    if [ "$is_resumed" = false ]; then
        clear
        echo -e "${CYAN}${BOLD}"
        echo "    ____  _                             "
        echo "   / __ )(_)__  __ __  ______ _____     "
        echo "  / __  / / / / / / / / / __ \`/ __ \    "
        echo " / /_/ / / /_/ / /_/ / / /_/ / / / /    "
        echo "/_____/_/\__, /\__,_/\__,_/_/ /_/       "
        echo "        /____/  Fedora Install Engine"
        echo -e "${CYAN}------------------------------------------------------${NC}"
        echo -e "  ⚡ Fast Deployment | Auto-Sync Remote |"
        echo -e "${CYAN}------------------------------------------------------${NC}\n"
    fi

    # --- 1. 【核心修复】：加载所有模块 ---
    if [ -d "$SCRIPTS_DIR" ]; then
        # 显式先加载 utils.sh（如果存在）
        [ -f "$SCRIPTS_DIR/utils.sh" ] && source "$SCRIPTS_DIR/utils.sh"
        
        for script in "$SCRIPTS_DIR"/*.sh; do
            if [ -f "$script" ] && [[ "$script" != *"utils.sh" ]]; then
                chmod +x "$script"
                source "$script"
            fi
        done
    else
        echo -e "${RED}❌ Error: Scripts directory not found at $SCRIPTS_DIR${NC}"
        exit 1
    fi

    # --- 执行流程 ---
    
    # 仅在非恢复状态下执行备份和更新询问
    if [ "$is_resumed" = false ]; then
        # Phase 1: 磁盘防护与备份
        if command -v setup_snapper_and_backup &> /dev/null; then
            setup_snapper_and_backup
        else
            echo -e "${RED}>> Error: setup_snapper_and_backup function not loaded!${NC}"
        fi

        echo -e "\n${BLUE}>> Snapper configuration finished. Entering desktop deployment...${NC}"

        # ========================================================
        # 【新增逻辑】：在备份完成后，询问是否拉取更新
        # ========================================================
        if [ -d ".git" ] && command -v git &> /dev/null; then
            echo -e "\n${BLUE}=====================================================${NC}"
            echo -e "${GREEN}  Repository Update Check${NC}"
            echo -e "${BLUE}=====================================================${NC}"
            
            read -p "Check and pull the latest remote code? (y/N): " confirm_update
            
            if [[ "$confirm_update" =~ ^[Yy]$ ]]; then
                local TIMEOUT_SEC=5
                echo -e "${YELLOW}>> Checking for remote updates (Timeout: ${TIMEOUT_SEC}s)...${NC}"
                
                # 使用 timeout 命令限制 git fetch 的执行时间
                if ! timeout "${TIMEOUT_SEC}" git fetch --quiet 2>/dev/null; then
                    echo -e "${YELLOW}⚠️  Update check timed out or network failed. Skipping...${NC}"
                else
                    LOCAL=$(git rev-parse @)
                    REMOTE=$(git rev-parse @{u} 2>/dev/null)

                    if [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
                        echo -e "${CYAN}>> New version detected, pulling changes...${NC}"
                        if timeout "${TIMEOUT_SEC}" git pull --quiet; then
                            echo -e "${GREEN}✅ Repository code updated.${NC}"
                            echo -e "${YELLOW}>> Restarting script to apply new changes...${NC}"
                            sync && sleep 0.5 
                            # 拉取成功后重启脚本，附带 --resumed 参数跳过 Phase 1
                            exec bash "$0" --resumed "$@"
                            exit 0
                        else
                            echo -e "${RED}❌ Pull failed. Continuing with local version.${NC}"
                        fi
                    else
                        echo -e "${GREEN}✅ Repository is already up to date.${NC}"
                    fi
                fi
            else
                echo -e "${CYAN}>> Skipped repository update.${NC}"
            fi
        fi
    fi

    # Phase 2: 桌面环境部署选择菜单
    echo -e "\n${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [Phase 2] Desktop Environment (DE/WM) Selection${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo "  1) 🟢 GNOME Desktop (Official Standard)"
    echo "  2) 🔵 KDE Plasma (Highly Customized)"
    echo "  3) 🟣 Niri Window Manager (Tiling Wayland)"
    echo "  0) ⏭️  Skip Desktop Deployment (Base System Only)"
    read -p "Please select your environment [0-3]: " desktop_opt

    case "$desktop_opt" in
        1)
            [ "$(type -t install_desktop_gnome)" == "function" ] && install_desktop_gnome || echo -e "${RED}❌ Error: GNOME module missing.${NC}"
            ;;
        2)
            [ "$(type -t install_desktop_kde)" == "function" ] && install_desktop_kde || echo -e "${RED}❌ Error: KDE module missing.${NC}"
            ;;
        3)
            [ "$(type -t install_desktop_niri)" == "function" ] && install_desktop_niri || echo -e "${RED}❌ Error: Niri module missing.${NC}"
            ;;
        *)
            echo -e "${YELLOW}>> Skipping desktop deployment.${NC}"
            ;;
    esac

    # Phase 3: 登录管理器部署 (Greetd/Tuigreet)
    # 【位置修正】：必须在 main 函数内部，并在 desktop_opt 赋值之后
    if [[ "$desktop_opt" == "3" ]]; then
        echo -e "\n${BLUE}>> Finalizing with Display Manager setup...${NC}"
        if command -v setup_greetd_niri &> /dev/null; then
            setup_greetd_niri
        else
            echo -e "${RED}❌ Error: setup_greetd_niri function not found!${NC}"
        fi
    fi
    
    echo -e "\n${GREEN}✨ System deployment flow completed!${NC}"
}

# 启动程序
main "$@"