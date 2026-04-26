install_desktop_kde() {
    echo -e "\n${YELLOW}>> 准备安装 KDE Plasma...${NC}"
    read -p "确认执行？[y/N]: " cf
    if [[ $cf == [yY] ]]; then
        safe_install "@kde-desktop-environment"
        echo -e "${GREEN}>> KDE Plasma 处理完毕。${NC}\n"
    else
        echo -e "已取消。\n"
    fi
}