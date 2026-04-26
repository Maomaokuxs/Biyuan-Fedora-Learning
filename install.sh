#!/bin/bash

# --- 1. 系统校验与环境自愈 ---
# 增加系统校验：确保是 Fedora
if [ ! -f /etc/fedora-release ]; then
    echo -e "\033[1;31m错误: 检测到当前系统不是 Fedora Linux。\033[0m"
    echo -e "\033[1;33m本脚本包含针对 Btrfs 和 DNF 的深度定制，已终止运行。\033[0m"
    exit 1
fi

echo "正在检查并修复基础运行环境..."
for cmd in stow figlet git curl; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "\033[1;33m>> 正在补充安装缺失工具: $cmd\033[0m"
        sudo dnf install -y $cmd &> /dev/null
    fi
done

# --- 2. 全局变量导出 ---
export REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
export DOTFILES_DIR="$REPO_DIR/dotfiles"
export BACKUP_ROOT="$HOME/.dotfiles_backup"

export BLUE='\033[1;34m'
export GREEN='\033[1;32m'
export YELLOW='\033[1;33m'
export RED='\033[1;31m'
export NC='\033[0m'

# --- 3. 模块加载 ---
# 确保在仓库目录下加载，防止路径错误
source "$REPO_DIR/scripts/utils.sh"
source "$REPO_DIR/scripts/01_snapper_config.sh"
source "$REPO_DIR/scripts/02_base_env.sh"
source "$REPO_DIR/scripts/03_gpu_drivers.sh"
source "$REPO_DIR/scripts/04_desktop_niri.sh"
source "$REPO_DIR/scripts/05_desktop_kde.sh"
source "$REPO_DIR/scripts/06_desktop_gnome.sh"

# --- 4. 仓库预检与自动重载逻辑 ---
clear
print_header

echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN}  [系统预检] 仓库状态检查${NC}"
echo -e "${BLUE}=====================================================${NC}"

cd "$REPO_DIR" || exit
echo -e "${BLUE}>> 正在同步云端更新信息...${NC}"
git fetch origin main -q

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse @{u})

if [ "$LOCAL" != "$REMOTE" ]; then
    echo -e "${YELLOW}>> 检测到远程仓库有更新！${NC}"
    read -p "是否现在同步并自动重新运行脚本？[y/N]: " pull_now
    if [[ $pull_now == [yY] ]]; then
        git pull origin main
        echo -e "${GREEN}>> 脚本已更新，正在自动重启引擎...${NC}"
        sleep 1
        # 核心修改：使用 exec 替换当前进程实现自动重启
        exec bash "$0" "$@"
    fi
else
    echo -e "${GREEN}✅ 仓库已是最新状态，无需同步。${NC}"
fi

# --- 5. 正式执行流程 ---
setup_snapper       # 阶段 1：底层快照与配置恢复 (包含颜色系统同步)
setup_base          # 阶段 2：基础环境
setup_gpu           # 阶段 3：显卡驱动

# --- 6. 阶段 4：桌面环境路由选择 ---
echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN}  [阶段 4] 视觉交互：桌面环境选择${NC}"
echo -e "${BLUE}=====================================================${NC}"

while true; do
    echo "  1) Niri 桌面环境 (包含 Starship, Waybar, Rofi 等)"
    echo "  2) KDE Plasma 桌面环境"
    echo "  3) GNOME 桌面环境"
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

# 清理残留
[ -f "1:30" ] && rm "1:30"

echo -e "\n${BLUE}✨ 部署任务全部完成！${NC}\n"