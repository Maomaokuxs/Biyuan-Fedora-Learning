#!/bin/bash
# 文件位置: ./install.sh

# --- 色彩定义 --- #
CYAN='\033[0;36m'; BLUE='\033[0;34m'; GREEN='\033[0;32m'; PURPLE='\033[0;35m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

# --- 主程序入口 --- # 
main() {
    # 状态标记：检查是否是更新后重新拉起的脚本
    # 防止脚本在自我更新并重启后，陷入死循环或重复执行已经完成的步骤
    # 用于变更 is_resumed 变量值，判断是否为脚本更新后重新启动，判断跳过开场问候，是否执行磁盘备份。
    # 使用 local 确保了 is_resumed 这个变量只属于 main 函数
    local is_resumed=false
    # 参数：--resumed（更新后重启，跳过开场与备份）、--yes（高危命令也不问，直接执行）、--update（检查并拉取仓库更新，不带则跳过不问）
    # CONFIRM_EACH 默认 y（utils.sh 里定）；--yes 改为 n
    local do_update=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --resumed) is_resumed=true ;;
            --yes) CONFIRM_EACH=n ;;
            --update) do_update=true ;;
            *) break ;;
        esac
        shift
    done

# --- 路径定义 --- #

    # 通过 cd "$(dirname "${BASH_SOURCE[0]}")" 动态获取，确保脚本在任何地方调用都能找到自身位置。
    REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    # 模块脚本存放目录
    SCRIPTS_DIR="$REPO_DIR/scripts"
    # 配置文件存放目录
    export DOTFILES_DIR="$REPO_DIR/dotfiles"
    export REPO_DIR

    # 如果是首次启动（非更新后重启），则显示开场问候
    # 透明执行流（借鉴 end-4/dots-hyprland）：先讲清楚要做什么，再动手，不放装饰横幅
    if [ "$is_resumed" = false ]; then
        clear
        echo -e "${CYAN}${BOLD}biyuan desktop${NC}"
        echo -e "${CYAN}--------------${NC}"
        echo "Hi there! Before we start:"
        echo
        echo "Quick overview about what this script does:"
        echo "  1. Back up the current system (snapshot + files)."
        echo "  2. Install the base environment and packages (dnf)."
        echo "  3. Deploy the desktop and its configs."
        echo "  4. Set up wallpaper, shell and the login manager."
        echo
        echo "Tips:"
        echo "  a) Anything it replaces is backed up first."
        echo "  b) Re-running is safe — already-deployed configs are skipped."
        echo "  c) Use --yes to run without asking even for high-risk commands."
        echo
        echo "Note: it does not touch disk layout or your data."
        echo
        # 开场门：只问一次 y/n，要不要开始（回车默认 y）；--yes 时跳过不问。
        # 普通命令只显示不问，高危命令（删/换包、全系统升级、改 /etc、改 grub、
        # 改启动目标与登录管理器、改用户组）执行前会单独问一次。
        if [ "${CONFIRM_EACH:-y}" != "n" ]; then
            printf "Ready to start? [Y/n]: "
            local go_ans
            read -r go_ans || go_ans="y"
            case "$go_ans" in
                n|N) echo -e "${RED}>> Aborted by user.${NC}"; exit 1 ;;
                *) ;;
            esac
        fi
    fi

    # --- 预热 sudo 权限：开场问完 y 之后才要密码，答 n 就不用输密码 ---
    sudo -v || exit 1

    # --- 1. 【核心修复】：加载所有模块 ---
    # 判断 scripts/ 目录是否存在
    if [ -d "$SCRIPTS_DIR" ]; then
        # 显式先加载 utils.sh（如果存在）
        [ -f "$SCRIPTS_DIR/utils.sh" ] && source "$SCRIPTS_DIR/utils.sh"
        # 遍历：寻找 scripts/ 目录下所有以 .sh 结尾的文件
        for script in "$SCRIPTS_DIR"/*.sh; do
            # [[ "$script" != *"utils.sh" ]] 确保刚才已经加载过的 utils.sh 不会被重复加载。
            if [ -f "$script" ] && [[ "$script" != *"utils.sh" ]]; then
                # 赋权：chmod +x "$script" 自动给子脚本添加执行权限
                chmod +x "$script"
                # 注入（Source）：source "$script"在当前进程中执行脚本
                source "$script"
            fi
        done
    else
        echo -e "${RED}❌ Error: Scripts directory not found at $SCRIPTS_DIR${NC}"
        exit 1
    fi

    # --- 0. by-mgr 先就绪：Phase 1 的物理备份改调 by-mgr snapshot，
    # 备份之前必须先有 by-mgr 本体（只拷仓库里的二进制，不依赖 stow 和装包）。
    # --resumed 时也跑一次：幂等，已就绪时不动。
    if command -v prepare_by_mgr &> /dev/null; then
        prepare_by_mgr || { echo -e "${RED}❌ Error: by-mgr is not ready, cannot back up.${NC}"; exit 1; }
    else
        echo -e "${RED}❌ Error: 'prepare_by_mgr' function not found!${NC}"
        exit 1
    fi

    # --- 执行流程 --- #
    
        # --- 备份与恢复 --- #

    # 仅在非恢复状态下执行备份和更新检查
    # 确保备份操作只在第一次启动时运行
    if [ "$is_resumed" = false ]; then
        # Phase 1: 磁盘防护与备份

        if command -v setup_snapper_and_backup &> /dev/null; then
            setup_snapper_and_backup
        else
            echo -e "${RED}>> Error: setup_snapper_and_backup function not loaded!${NC}"
        fi

        echo -e "\n${BLUE}>> Snapper configuration finished. Entering desktop deployment...${NC}"

       
        # 在备份完成后，带 --update 参数才检查并拉取更新，不带则直接跳过（不提问）
        # 以脚本所在目录（$REPO_DIR）为准，不依赖当前工作目录
        if [ "$do_update" = true ] && [ -d "$REPO_DIR/.git" ] && command -v git &> /dev/null; then
            echo -e "\n${BLUE}=====================================================${NC}"
            echo -e "${GREEN}              Repository Update Check${NC}"
            echo -e "${BLUE}=====================================================${NC}"
            
            local TIMEOUT_SEC=5
            echo -e "${YELLOW}>> Checking for remote updates (Timeout: ${TIMEOUT_SEC}s)...${NC}"
            
            # 使用 timeout 命令限制 git fetch 的执行时间
            if ! timeout "${TIMEOUT_SEC}" git -C "$REPO_DIR" fetch --quiet 2>/dev/null; then
                echo -e "${YELLOW}⚠️  Update check timed out or network failed. Skipping...${NC}"
            else
                LOCAL=$(git -C "$REPO_DIR" rev-parse @)
                REMOTE=$(git -C "$REPO_DIR" rev-parse @{u} 2>/dev/null)

                if [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
                    echo -e "${CYAN}>> New version detected, pulling changes...${NC}"
                    if timeout "${TIMEOUT_SEC}" git -C "$REPO_DIR" pull --quiet; then
                        echo -e "${GREEN}✅ Repository code updated.${NC}"
                        echo -e "${YELLOW}>> Restarting script to apply new changes...${NC}"
                        sync && sleep 0.5
                        # 拉取成功后重启脚本，附带 --resumed 参数跳过开场问候，跳过 Phase 1: 磁盘防护与备份
                        # 逐条确认的选择用环境变量带过去，重启后不再重问
                        export CONFIRM_EACH
                        exec bash "$0" --resumed "$@"
                        exit 0
                    else
                        echo -e "${RED}❌ Pull failed. Continuing with local version.${NC}"
                    fi
                else
                    echo -e "${GREEN}✅ Repository is already up to date.${NC}"
                fi
            fi
        fi
    fi

    # Phase 2: 桌面环境部署选择菜单
    echo -e "\n${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [Phase 2] Desktop Environment (DE/WM) Selection${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo "  1) GNOME Desktop (Official Standard)"
    echo "  2) KDE Plasma (Highly Customized)"
    echo "  3) Niri Window Manager (Tiling Wayland)"
    echo "  0) Skip Desktop Deployment (Base System Only)"
    read -p "Please select your environment [0-3]: " desktop_opt

    desktop_ok=1
    case "$desktop_opt" in
        1)
            if [ "$(type -t install_desktop_gnome)" == "function" ]; then
                install_desktop_gnome || { echo -e "${RED}❌ GNOME deployment failed (see above).${NC}"; desktop_ok=0; }
            else
                echo -e "${RED}❌ Error: GNOME module missing.${NC}"
                desktop_ok=0
            fi
            ;;
        2)
            if [ "$(type -t install_desktop_kde)" == "function" ]; then
                install_desktop_kde || { echo -e "${RED}❌ KDE deployment failed (see above).${NC}"; desktop_ok=0; }
            else
                echo -e "${RED}❌ Error: KDE module missing.${NC}"
                desktop_ok=0
            fi
            ;;
        3)
            # 部署失败时 install_desktop_niri 会 return 1，别再报“模块缺失”误导人
            if [ "$(type -t install_desktop_niri)" == "function" ]; then
                install_desktop_niri || { echo -e "${RED}❌ Niri deployment failed (see above).${NC}"; desktop_ok=0; }
            else
                echo -e "${RED}❌ Error: Niri module missing.${NC}"
                desktop_ok=0
            fi
            ;;
        *)
            echo -e "${YELLOW}>> Skipping desktop deployment.${NC}"
            ;;
    esac

    # 收尾：只有桌面阶段成功（或主动跳过）才报完成；失败则报未完成并返回非零退出码
    if [ "$desktop_ok" -eq 1 ]; then
        echo -e "\n${GREEN}✨ System deployment flow completed!${NC}"
    else
        echo -e "\n${RED}❌ Deployment incomplete: desktop deployment failed (see above).${NC}"
        return 1
    fi
}

# 启动程序
main "$@"