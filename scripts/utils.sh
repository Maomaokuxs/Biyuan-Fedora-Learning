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