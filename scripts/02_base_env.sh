setup_base() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 2] 核心基建：终端环境与系统更新${NC}"
    echo -e "${BLUE}=====================================================${NC}"

    echo -e "${YELLOW}检测到即将开始安装基础包，建议先更新系统内核与库。${NC}"
    echo -e "是否执行全系统更新 (dnf update)? [Y/n] (10秒后默认执行): "
    read -t 10 confirm_update
    confirm_update=${confirm_update:-Y}

    if [[ $confirm_update == [yY] ]]; then
        echo -e "${BLUE}>> 正在执行全系统更新...${NC}"
        sudo dnf update -y
        echo -e "${GREEN}✅ 系统更新完成。${NC}\n"
    fi

    read -p "安装核心基础工具 (git, curl, stow)? [y/N]: " res
    if [[ $res == [yY] ]]; then
        # 移除了 starship 和 fastfetch，它们现在由 Niri 模块负责
        safe_install "git curl htop stow"
        deploy_module "bash"
        echo -e "${GREEN}核心基础工具已就绪。${NC}\n"
    fi
}