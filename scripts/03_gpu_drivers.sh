setup_gpu() {
    # 打印驱动选择菜单
    echo "  1) NVIDIA Drivers | 2) AMD Enhancements | 3) Intel Enhancements | 0) Skip"
    read -p "Select Platform [0-3]: " gpu_opt
    gpu_opt=${gpu_opt:-0}

    # 检查是否跳过
    [[ "$gpu_opt" == "0" ]] && { echo -e "Skipped.\n"; return; }

    # 确认安装操作
    read -p ">> Confirm hardware acceleration package installation? [y/N]: " confirm
    [[ $confirm != [yY] ]] && return

    case $gpu_opt in
        1)
            # 配置 RPM Fusion 并安装 NVIDIA 闭源驱动
            echo -e "${YELLOW}Configuring RPM Fusion and installing NVIDIA proprietary drivers...${NC}"
            safe_install "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
            safe_install "akmod-nvidia xorg-x11-drv-nvidia-cuda"
            echo -e "${GREEN}✅ NVIDIA driver installation complete. (Reboot required)${NC}"
            ;;
        2)
            # 安装 AMD 相关加速包
            echo -e "${YELLOW}Installing AMD enhancement packages...${NC}"
            safe_install "mesa-vulkan-drivers mesa-va-drivers rocm-opencl radeontop"
            echo -e "${GREEN}✅ AMD enhancement packages installed successfully.${NC}"
            ;;
        3)
            # 安装 Intel 相关加速包
            echo -e "${YELLOW}Installing Intel enhancement packages...${NC}"
            safe_install "mesa-vulkan-drivers intel-media-driver"
            echo -e "${GREEN}✅ Intel enhancement packages installed successfully.${NC}"
            ;;
        *) 
            # 错误处理
            echo -e "${RED}Invalid option.${NC}" ;;
    esac
    echo ""
}