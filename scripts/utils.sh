# --- VM 环境检测 ---
is_vm() {
    if command -v systemd-detect-virt &> /dev/null; then
        systemd-detect-virt -q && return 0
    fi
    # 降级检测
    if grep -qi "hypervisor" /proc/cpuinfo 2>/dev/null; then
        return 0
    fi
    return 1
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