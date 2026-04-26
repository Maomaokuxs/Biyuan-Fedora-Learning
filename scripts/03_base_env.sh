setup_base() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 3] 核心基建：终端环境与基础工具${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    read -p "同步 Bash/Starship 并安装基础包? [y/N]: " res
    if [[ $res == [yY] ]]; then
        safe_install "git curl fastfetch htop stow starship"
        deploy_module "bash"
        deploy_module "starship"
        echo -e "${GREEN}基础环境已就绪。${NC}\n"
    else
        echo -e "已跳过。\n"
    fi
}