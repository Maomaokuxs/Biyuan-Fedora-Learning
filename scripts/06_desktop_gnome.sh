install_desktop_gnome() {
    echo -e "\n${YELLOW}>> 准备安装 GNOME Desktop...${NC}"
    read -p "确认执行？[y/N]: " cf
    if [[ $cf == [yY] ]]; then
        safe_install "@workstation-product-environment"
        echo -e "${GREEN}>> GNOME Desktop 处理完毕。${NC}\n"
    else
        echo -e "已取消。\n"
    fi
}