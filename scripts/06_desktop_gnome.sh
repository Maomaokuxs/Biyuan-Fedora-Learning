install_desktop_gnome() {
    # 打印安装准备提示
    echo -e "\n${YELLOW}>> Preparing to install GNOME Desktop...${NC}"
    
    # 确认执行安装
    read -p "Confirm execution? [y/N]: " cf
    if [[ $cf == [yY] ]]; then
        # 执行安装 GNOME 桌面环境（Fedora 官方 Workstation 环境）
        safe_install "@workstation-product-environment"
        echo -e "${GREEN}>> GNOME Desktop deployment complete.${NC}\n"
    else
        # 取消安装
        echo -e "Installation cancelled.\n"
    fi
}