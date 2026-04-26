# --- 标题打印 ---
print_header() {
    if ! command -v figlet &> /dev/null; then sudo dnf install -y figlet &> /dev/null; fi
    echo -e "${BLUE}"
    figlet -f block "BIYUAN"
    figlet -f block "FEDORA"
    echo -e "${NC}-----------------------------------------------------"
    echo -e "       模块化环境向导程序 | 智能引擎版 | 2026.04"
    echo -e "-----------------------------------------------------\n"
}

# --- 预检与云端同步 ---
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

# --- 智能包管理器 (增强日志输出版) ---
safe_install() {
    local pkgs="$1"
    local to_install=""
    local already_installed=""

    for pkg in $pkgs; do
        if [[ "$pkg" == @* ]] || [[ "$pkg" == http* ]]; then
            # 组包或直链，让 dnf 自己去判断
            to_install="$to_install $pkg"
        elif rpm -q "$pkg" &> /dev/null; then
            # 本地已安装
            already_installed="$already_installed $pkg"
        else
            # 缺失，需要安装
            to_install="$to_install $pkg"
        fi
    done

    # 整理格式
    to_install=$(echo "$to_install" | xargs)
    already_installed=$(echo "$already_installed" | xargs)

    # 打印已存在的包 (透明反馈，化解误解)
    if [ -n "$already_installed" ]; then
        echo -e "${GREEN}>> [检测] 以下依赖已存在，跳过安装: ${NC}$already_installed"
    fi

    # 安装缺失的包
    if [ -n "$to_install" ]; then
        echo -e "${YELLOW}>> [执行] 正在补充安装缺失包: ${NC}$to_install"
        sudo dnf install -y --setopt=strict=0 $to_install || true
        echo -e "${GREEN}>> [完成] 软件包补充环节结束。${NC}"
    else
        echo -e "${GREEN}>> [跳过] 所有底层依赖均已满足，直接进入环境配置。${NC}"
    fi
}

# --- Stow 软链接部署 ---
deploy_module() {
    local module_name=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local bdir="$BACKUP_ROOT/${timestamp}_$module_name"
    local check_path=""
    
    # 修正 bashrc 的判断路径
    [ "$module_name" == "bash" ] && check_path="$HOME/.bashrc" || check_path="$HOME/.config/$module_name"

    # 如果有旧配置，执行备份
    if [ -e "$check_path" ] && [ ! -L "$check_path" ]; then
        echo -e "${YELLOW}>> [备份] 发现旧配置，正在备份: $module_name${NC}"
        mkdir -p "$bdir"
        cp -rf "$check_path" "$bdir/"
        rm -rf "$check_path" # 移除物理文件以便 stow 可以创建软链接
    fi

    cd "$DOTFILES_DIR"
    stow -v -t ~ "$module_name" 2>/dev/null
    echo -e "${BLUE}>> [配置] $module_name 模块映射已应用。${NC}"
}