setup_gpu() {
    echo "  1) NVIDIA 驱动 | 2) AMD 增强 | 3) Intel 增强 | 0) 跳过"
    read -p "选择平台 [0-3]: " gpu_opt
    gpu_opt=${gpu_opt:-0}

    [[ "$gpu_opt" == "0" ]] && { echo -e "已跳过。\n"; return; }

    read -p ">> 确认安装硬件加速包？[y/N]: " confirm
    [[ $confirm != [yY] ]] && return

    case $gpu_opt in
        1)
            echo -e "${YELLOW}配置 RPM Fusion 并安装 NVIDIA 闭源驱动...${NC}"
            safe_install "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
            safe_install "akmod-nvidia xorg-x11-drv-nvidia-cuda"
            echo -e "${GREEN}✅ NVIDIA 驱动安装完成。(需重启生效)${NC}"
            ;;
        2)
            safe_install "mesa-vulkan-drivers mesa-va-drivers rocm-opencl radeontop"
            echo -e "${GREEN}✅ AMD 增强包安装完成。${NC}"
            ;;
        3)
            safe_install "mesa-vulkan-drivers intel-media-driver"
            echo -e "${GREEN}✅ Intel 增强包安装完成。${NC}"
            ;;
        *) echo -e "${RED}无效选项。${NC}" ;;
    esac
    echo ""
}