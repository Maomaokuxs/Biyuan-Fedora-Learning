print_header() {
    if ! command -v figlet &> /dev/null; then sudo dnf install -y figlet &> /dev/null; fi
    echo -e "${BLUE}"
    figlet -f block "BIYUAN"
    figlet -f block "FEDORA"
    echo -e "${NC}-----------------------------------------------------"
    echo -e "       模块化环境向导程序 | 语义化架构版 | 2026.04"
    echo -e "-----------------------------------------------------\n"
}

sync_and_snapshot() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统预检] 云端同步与安全快照检查${NC}"
    echo -e "${BLUE}=====================================================${NC}"

    cd "$REPO_DIR" || return
    if [ -d ".git" ]; then
        echo "正在检查仓库更新..."
        git fetch origin main -q 2>/dev/null
        if [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u} 2>/dev/null)" ]; then
            read -p "检测到云端有更新，是否拉取？[y/N]: " pull_confirm
            if [[ $pull_confirm == [yY] ]]; then
                git pull origin main && echo -e "${GREEN}更新成功，重启脚本...${NC}" && sleep 1 && exec bash "$REPO_DIR/install.sh" "$@"
            fi
        fi
    fi

    # 自动快照检测与带时间戳的执行
    if command -v snapper &> /dev/null && [ "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        echo -e "${YELLOW}检测到系统已配置 Snapper 快照保护。${NC}"
        read -p "是否在部署前创建安全快照？[y/N]: " snap_pre
        if [[ $snap_pre == [yY] ]]; then
            local ts=$(date "+%Y-%m-%d %H:%M:%S")
            local desc="Biyuan-Fedora-Install 开始于 $ts"
            echo "正在生成快照: [$desc]..."
            sudo snapper create --description "$desc"
            echo -e "${GREEN}✅ 预执行快照已创建。${NC}"
        fi
    fi
    echo ""
}

safe_install() {
    local pkgs="$1"
    echo -e "${YELLOW}>> 正在安装软件包: $pkgs${NC}"
    sudo dnf install -y --setopt=strict=0 $pkgs || true
    echo -e "${GREEN}>> 软件包安装环节结束。${NC}"
}

deploy_module() {
    local module_name=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local bdir="$BACKUP_ROOT/${timestamp}_$module_name"
    local check_path=""
    [ "$module_name" == "bash" ] && check_path="$HOME/.bashrc" || check_path="$HOME/.config/$module_name"

    if [ -e "$check_path" ]; then
        echo -e "${YELLOW}>> 备份旧配置: $module_name${NC}"
        mkdir -p "$bdir"
        cp -rf "$check_path" "$bdir/"
    fi

    cd "$DOTFILES_DIR"
    stow -v -t ~ "$module_name" 2>/dev/null
}