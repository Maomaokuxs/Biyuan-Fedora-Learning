install_desktop_niri() {
    echo -e "\n${YELLOW}>> 准备部署 Niri 全集成方案 (含 Starship 与 KDE 组件)...${NC}"
    read -p "确认执行？[y/N]: " cf
    if [[ $cf == [yY] ]]; then
        # 包含你提供的所有软件包，并修正了 firefox 的拼写
        local niri_pkgs="fastfetch swww waypaper rofi hyprlock hypridle starship firefox hellwal PackageKit-Qt6 dolphin mako plasma-discover kmenuedit niri waybar"
        
        safe_install "$niri_pkgs"

        # 执行配置映射 (Stow)
        # 确保你的 dotfiles 目录下有对应的文件夹名称
        deploy_module "niri"
        deploy_module "waybar"
        deploy_module "rofi"
        deploy_module "hypr"      # 对应 hyprlock/hypridle
        deploy_module "starship"  # 从基础环境移动到此处
        deploy_module "mako"      # 新增 mako 通知配置映射
        
        echo -e "${GREEN}>> Niri 桌面环境及相关组件处理完毕。${NC}\n"
    else
        echo -e "已取消。\n"
    fi
}