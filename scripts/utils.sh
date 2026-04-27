# --- 标题打印 ---
print_header() {
    if ! command -v figlet &> /dev/null; then sudo dnf install -y figlet &> /dev/null; fi
    echo -e "${BLUE}"
    figlet -f block "BIYUAN"
    figlet -f block "FEDORA"
    echo -e "${NC}-----------------------------------------------------"
    # 【修复点】：这里末尾漏掉了一个双引号 "
    echo -e "                Modular Environment Wizard"
    echo -e "-----------------------------------------------------\n"
}

# --- 预检与云端同步 ---
sync_and_snapshot() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [System Check] Cloud Sync & Security Snapshot${NC}"
    echo -e "${BLUE}=====================================================${NC}"

    cd "$REPO_DIR" || return
    if [ -d ".git" ]; then
        echo "Checking for repository updates..."
        git fetch origin main -q 2>/dev/null
        if [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u} 2>/dev/null)" ]; then
            read -p "Cloud updates detected. Pull latest changes? [y/N]: " pull_confirm
            if [[ $pull_confirm == [yY] ]]; then
                git pull origin main && echo -e "${GREEN}Update successful. Restarting script...${NC}" && sleep 1 && exec bash "$REPO_DIR/install.sh" "$@"
            fi
        fi
    fi

    # 自动快照检测与带时间戳的执行
    if command -v snapper &> /dev/null && [ "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        echo -e "${YELLOW}System is protected by Snapper snapshots.${NC}"
        read -p "Create a security snapshot before deployment? [y/N]: " snap_pre
        if [[ $snap_pre == [yY] ]]; then
            local ts=$(date "+%Y-%m-%d %H:%M:%S")
            local desc="Biyuan-Fedora-Install started at $ts"
            echo "Generating snapshot: [$desc]..."
            sudo snapper create --description "$desc"
            echo -e "${GREEN}✅ Pre-deployment snapshot created.${NC}"
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

    # 打印已存在的包 (透明反馈)
    if [ -n "$already_installed" ]; then
        echo -e "${GREEN}>> [Check] The following dependencies are present, skipping: ${NC}$already_installed"
    fi

    # 安装缺失的包
    if [ -n "$to_install" ]; then
        echo -e "${YELLOW}>> [Execute] Installing missing packages: ${NC}$to_install"
        sudo dnf install -y --setopt=strict=0 $to_install || true
        echo -e "${GREEN}>> [Done] Package installation phase complete.${NC}"
    else
        echo -e "${GREEN}>> [Skip] All base dependencies met. Proceeding to configuration.${NC}"
    fi
}

# --- Stow 软链接部署 ---
deploy_module() {
    local module_name=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    # 如果没有定义 BACKUP_ROOT，给一个默认值
    : "${BACKUP_ROOT:=$HOME/.dotfiles_backup}"
    local bdir="$BACKUP_ROOT/${timestamp}_$module_name"
    local check_path=""
    
    # 修正 bashrc 的判断路径
    if [ "$module_name" == "bash" ]; then
        check_path="$HOME/.bashrc"
    else
        check_path="$HOME/.config/$module_name"
    fi

    # 如果有旧配置，执行备份
    if [ -e "$check_path" ] && [ ! -L "$check_path" ]; then
        echo -e "${YELLOW}>> [Backup] Legacy config found. Backing up: $module_name${NC}"
        mkdir -p "$bdir"
        cp -rf "$check_path" "$bdir/"
        rm -rf "$check_path" # 移除物理文件以便 stow 可以创建软链接
    fi

    cd "$DOTFILES_DIR"
    # 使用 -R 替代 -v -t ~ 往往更简洁
    stow -R -t ~ "$module_name" 2>/dev/null
    echo -e "${BLUE}>> [Config] Module mapping applied: $module_name${NC}"
}