install_desktop_niri() {
    echo -e "\n${YELLOW}>> 准备部署 Niri 全集成方案...${NC}"
    read -p "确认执行？[y/N]: " cf
    if [[ $cf == [yY] ]]; then
        safe_install "niri waybar rofi-wayland hypridle hyprlock python3-pywal"
        deploy_module "niri"
        deploy_module "waybar"
        deploy_module "rofi"
        deploy_module "hypr"
        echo -e "${GREEN}>> Niri 桌面环境处理完毕。${NC}\n"
    else
        echo -e "已取消。\n"
    fi
}