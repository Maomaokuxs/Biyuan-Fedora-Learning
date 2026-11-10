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
        x sudo dnf install -y --setopt=strict=0 $to_install
        echo -e "${GREEN}>> [Done] Package installation phase complete.${NC}"
    else
        echo -e "${GREEN}>> [Skip] All base dependencies met. Proceeding to configuration.${NC}"
    fi
}

# --- 透明执行流（借鉴 end-4/dots-hyprland 的 v()/x()） ---
# 每条关键命令执行前先展示出来（只显示、不问）；失败可重试/忽略/退出。
# 只有高危命令才执行前问一次，用 hv()/hx()：删/换包、全系统升级、改 /etc、
# 改 grub、改启动目标与登录管理器、改用户组。--yes（CONFIRM_EACH=n）时连高危也不问；
# 更新重启时靠 export CONFIRM_EACH 带过去。非交互（stdin 不是 tty）时一律直接执行。

CONFIRM_EACH="${CONFIRM_EACH:-y}"

# 执行前停一下，等用户按回车（Ctrl-C 中止）
pause() {
    echo -e "${YELLOW}(Ctrl-C to abort, Enter to proceed)${NC}"
    read -r || true
}

# v: 只展示、直接执行，不问。返回命令的退出码（if 条件里照常用）。
v() {
    local cmd_str
    printf -v cmd_str '%q ' "$@"
    cmd_str="${cmd_str% }"
    echo -e "${GREEN}>> ${cmd_str}${NC}"
    "$@"
    return $?
}

# hv: 高危命令专用——展示后问一次再执行。返回 0=已执行且成功（或跳过），非 0=命令失败的退出码；
# 选 e 时直接 exit 1 结束整个安装（仅在直接调用时生效，别放进 $() 或管道里）。
# 读不到输入（EOF：Ctrl-D）时按跳过处理，不执行。
hv() {
    local cmd_str
    printf -v cmd_str '%q ' "$@"
    cmd_str="${cmd_str% }"
    echo "############################################################"
    echo -e "[install.sh]: Next command:"
    echo -e "${GREEN}${cmd_str}${NC}"
    if [ "$CONFIRM_EACH" != "y" ] || [ ! -t 0 ]; then
        "$@"
        return $?
    fi
    local ans
    printf "Execute?  y = Yes   e = Exit now   s = Skip this command   yesforall = Yes, don't ask again\n====> "
    if ! read -r ans; then
        echo -e "${CYAN}>> [Skip] No input (EOF), not executed.${NC}"
        return 0
    fi
    case "$ans" in
        e|E) echo -e "${RED}>> Aborted by user.${NC}"; exit 1 ;;
        s|S) echo -e "${CYAN}>> [Skip] ${cmd_str}${NC}"; return 0 ;;
        yesforall) CONFIRM_EACH=n ;;
        *) ;;
    esac
    "$@"
    return $?
}

# x: 带重试的 v。命令失败时问 r=重试（默认）/ e=退出 / i=忽略并继续。
# 读不到输入（EOF：管道关了、/dev/null、Ctrl-D）时按忽略处理，不重试、不死循环。
# 注意：不能用 [ ! -t 0 ] 直接跳过提问——管道里可能正喂着答案（r/i），要先读，读不到才忽略。
x() {
    local rc
    while true; do
        v "$@"
        rc=$?
        [ "$rc" -eq 0 ] && return 0
        echo -e "${RED}>> Command failed (exit $rc): ${NC}$*"
        local ans
        printf "Retry?  r = Repeat (DEFAULT)   e = Exit   i = Ignore and continue\n====> "
        if ! read -r ans; then
            echo -e "${YELLOW}>> [Ignore] No input (EOF), continuing despite failure.${NC}"
            return 0
        fi
        case "$ans" in
            e|E) echo -e "${RED}>> Aborted by user.${NC}"; exit 1 ;;
            i|I) echo -e "${YELLOW}>> [Ignore] Continuing despite failure.${NC}"; return 0 ;;
            *) ;;
        esac
    done
}

# hx: 带重试的 hv。高危命令失败时问 r=重试（默认）/ e=退出 / i=忽略并继续。
hx() {
    local rc
    while true; do
        hv "$@"
        rc=$?
        [ "$rc" -eq 0 ] && return 0
        echo -e "${RED}>> Command failed (exit $rc): ${NC}$*"
        local ans
        printf "Retry?  r = Repeat (DEFAULT)   e = Exit   i = Ignore and continue\n====> "
        if ! read -r ans; then
            echo -e "${YELLOW}>> [Ignore] No input (EOF), continuing despite failure.${NC}"
            return 0
        fi
        case "$ans" in
            e|E) echo -e "${RED}>> Aborted by user.${NC}"; exit 1 ;;
            i|I) echo -e "${YELLOW}>> [Ignore] Continuing despite failure.${NC}"; return 0 ;;
            *) ;;
        esac
    done
}