install_desktop_kde() {
    # 打印安装准备提示
    echo -e "\n${YELLOW}>> Preparing to install KDE Plasma...${NC}"
    
    # 确认执行安装
    read -p "Confirm execution? [y/N]: " cf
    if [[ $cf == [yY] ]]; then
        # 执行安装 KDE 桌面环境包组
        safe_install "@kde-desktop-environment"
        echo -e "${GREEN}>> KDE Plasma deployment complete.${NC}\n"
    else
        # 取消安装
        echo -e "Installation cancelled.\n"
    fi
}