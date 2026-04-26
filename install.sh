#!/bin/bash

# --- 1. 基础环境自愈 (筑基) ---
# 无论如何，先确保这几个关键工具存在，否则后续 source 都会报错
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

# 导出颜色变量供子脚本使用
export BLUE='\033[1;34m'
export GREEN='\033[1;32m'
export YELLOW='\033[1;33m'
export RED='\033[1;31m'
export NC='\033[0m'

# --- 系统校验 (新增) ---
if [ ! -f /etc/fedora-release ]; then
    echo -e "${RED}错误: 检测到当前系统不是 Fedora Linux。${NC}"
    echo -e "${YELLOW}本脚本专为 Fedora 系统管理设计，已终止运行。${NC}"
    exit 1
fi

# --- 3. 模块加载 (顺序加载) ---
# 注意：这里只 source 包含函数的脚本，不直接执行
source "$REPO_DIR/scripts/utils.sh"
source "$REPO_DIR/scripts/01_snapper_config.sh"
source "$REPO_DIR/scripts/02_base_env.sh"
source "$REPO_DIR/scripts/03_gpu_drivers.sh"
source "$REPO_DIR/scripts/04_desktop_niri.sh"
source "$REPO_DIR/scripts/05_desktop_kde.sh"
source "$REPO_DIR/scripts/06_desktop_gnome.sh"

# --- 4. 严格执行逻辑流 (核心修复) ---
# 我们不再在 sync_and_snapshot 里使用 exec，而是通过逻辑控制
clear
print_header

# [预检阶段] 仅执行同步，不在此处重启
echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN}  [系统预检] 仓库状态检查${NC}"
echo -e "${BLUE}=====================================================${NC}"
cd "$REPO_DIR" || exit
git fetch origin main -q
if [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u})" ]; then
    echo -e "${YELLOW}>> 检测到远程仓库有更新。${NC}"
    read -p "是否现在同步并应用新脚本？[y/N]: " pull_now
    if [[ $pull_now == [yY] ]]; then
        git pull origin main
        echo -e "${GREEN}>> 脚本已更新，请重新运行 ./install.sh 以应用改动。${NC}"
        exit 0  # 安全退出，由用户手动重新运行，确保加载最新函数
    fi
fi

# [正式执行阶段] 锁死顺序，任何一个失败或跳过都会按照函数内部逻辑处理
setup_snapper       # 阶段 1：恢复与快照
setup_base          # 阶段 2：基础环境
setup_gpu           # 阶段 3：显卡驱动

# --- 5. 阶段 4：桌面环境路由选择 ---
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

# 清理那个奇怪的报错残留文件
[ -f "1:30" ] && rm "1:30"

echo -e "\n${BLUE}✨ 部署任务全部完成！建议重启系统以应用更改。${NC}\n"