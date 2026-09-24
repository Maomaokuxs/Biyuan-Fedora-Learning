#!/bin/bash
# 文件位置: scripts/03_gpu_drivers.sh
# 描述: 智能显卡驱动部署模块 (支持自动检测、手动覆盖与单包报错兜底)
# 独立运行时自动加载依赖
[ "${BASH_SOURCE[0]}" == "${0}" ] && SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) && [ -f "$SCRIPT_DIR/utils.sh" ] && source "$SCRIPT_DIR/utils.sh"

# --- 1. 仓库检测与自愈机制 --- # 
# 检查并自动添加 RPM Fusion（Free 和 Non-Free）第三方仓库
ensure_rpmfusion() {
    echo -e "${BLUE}>> Checking required repositories (RPM Fusion)...${NC}"
    local repo_added=false

    if ! dnf repolist | grep -qi "rpmfusion-free"; then
        echo -e "${YELLOW}>> [Action] RPM Fusion Free is missing. Adding...${NC}"
        sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
        repo_added=true
    fi

    if ! dnf repolist | grep -qi "rpmfusion-nonfree"; then
        echo -e "${YELLOW}>> [Action] RPM Fusion Non-Free is missing. Adding...${NC}"
        sudo dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
        repo_added=true
    fi

    if [ "$repo_added" = true ]; then
        echo -e "${GREEN}✅ RPM Fusion Repositories are ready.${NC}"
    fi
}

# --- 2. 核心安装与兜底引擎 --- #
execute_installation() {
    local target_name="$1"
    local extra_opts=""
    shift
    
    # 检测第一个参数是否是以 "-" 开头的 DNF 选项（如 --allowerasing）
    if [[ "$1" == -* ]]; then
        extra_opts="$1"
        shift
    fi
    
    local pkgs=("$@")
    
    echo -e "${YELLOW}>> Deploying $target_name Drivers...${NC}"
    # 打印时展示附加参数
    echo -e "${CYAN}>> Command: sudo dnf install -y $extra_opts ${pkgs[*]}${NC}"
    
    # 尝试批量安装（带上 extra_opts）
    if ! sudo dnf install -y $extra_opts "${pkgs[@]}"; then
        echo -e "${RED}⚠️  Installation encountered errors. Running fallback check...${NC}"
        # 兜底机制：逐个检查哪个包失败了
        for pkg in "${pkgs[@]}"; do
            # 如果是虚包或者被降级/替换安装的包，rpm -q 有时查不到精确名，这里只做未安装提示
            if ! rpm -q "$pkg" &>/dev/null; then
                echo -e "${RED}❌ FAILED: Package '$pkg' could not be installed.${NC}"
                echo -e "${YELLOW}   Suggestion: Check your network, or the package name might have changed in this Fedora version.${NC}"
            fi
        done
    else
        echo -e "${GREEN}✅ $target_name Drivers installed successfully!${NC}"
    fi
}

# --- 3. 驱动包具体定义 ---
install_amd_drivers() {
    # 步骤 1：安装 Vulkan 基础驱动及工具（正常安装）
    execute_installation "AMD Vulkan" mesa-vulkan-drivers vulkan-loader libva-utils
    
    # 步骤 2：安装 Freeworld 硬件加速驱动（传入 --allowerasing 参数）
    execute_installation "AMD (Freeworld)" "--allowerasing" mesa-va-drivers-freeworld mesa-vdpau-drivers-freeworld
}

# 安装最新的 intel-media-driver，确保 Intel 核显或独显的视频硬解正常
install_intel_drivers() {
    execute_installation "Intel" intel-media-driver libva-utils
}

# 安装最稳健的 akmod-nvidia（会在内核更新时自动重新编译）以及 CUDA 支持
install_nvidia_drivers() {
    # 移除了废弃的 nvidia-vaapi-driver，保留 libva-nvidia-driver 即可
    execute_installation "NVIDIA (Proprietary)" akmod-nvidia xorg-x11-drv-nvidia-cuda libva-nvidia-driver libva-utils

    # 防黑屏：akmod 默认异步编译，模块没好就重启进新内核必黑；
    # 这里手动全编： except 最旧内核（留作保命 fallback，不碰）；
    # 只有一个内核就直接编它。编完逐个验，有一个失败就红字点名。
    echo -e "${YELLOW}>> Building NVIDIA kernel modules now (do NOT reboot until done)...${NC}"
    mapfile -t _kernels < <(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V)
    if [ ${#_kernels[@]} -eq 0 ]; then
        echo -e "${RED}❌ 内核列表为空，无法编译，中止（先修 rpm/dnf）。${NC}"
        return 1
    fi
    local _targets=()
    if [ ${#_kernels[@]} -le 1 ]; then
        _targets=("${_kernels[@]}")
        echo -e "${CYAN}>> 单内核，直接编译：${_targets[*]}${NC}"
    else
        _targets=("${_kernels[@]:1}")
        echo -e "${CYAN}>> 跳过最旧保命内核 ${_kernels[0]}，编译：${_targets[*]}${NC}"
    fi
    local _fail=()
    for _k in "${_targets[@]}"; do
        sudo dnf install -y "kernel-devel-$_k" --skip-unavailable
        sudo akmods --force --kernels "$_k"
        # 注：模块为压缩格式 nvidia.ko.xz，通配匹配
        if ls "/lib/modules/$_k/extra/nvidia/nvidia.ko"* 2>/dev/null | grep -q .; then
            echo -e "${GREEN}✅ NVIDIA kmod ready for $_k.${NC}"
            sudo dracut --kver "$_k" -f
        else
            echo -e "${RED}❌ NVIDIA kmod MISSING for $_k — 别进这个内核。${NC}"
            _fail+=("$_k")
        fi
    done
    if [ ${#_fail[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ initramfs rebuilt, safe to reboot.${NC}"
    else
        echo -e "${YELLOW}   等 akmods 后台编完（journalctl -u akmods -f），或重跑本脚本。${NC}"
    fi
}

# --- 4. 主干交互逻辑 ---
setup_gpu_drivers() {
    # VM 环境自动跳过
    if is_vm; then
        echo -e "\n${YELLOW}=====================================================${NC}"
        echo -e "${YELLOW}  ⚡ Running inside a virtual machine.${NC}"
        echo -e "${YELLOW}  GPU driver installation skipped (not applicable).${NC}"
        echo -e "${YELLOW}=====================================================${NC}"
        return 0
    fi

    echo -e "\n${BLUE}=====================================================${NC}"
    echo -e "${GREEN}          GPU Acceleration Setup${NC}"
    echo -e "${BLUE}=====================================================${NC}"

    # 内核一览：驱动要装在正用的内核上；刚更完内核没重启的话先列出来，
    # 手动重启进新内核再跑（本脚本不自动重启）。
    echo -e "${CYAN}>> Installed kernels (running: $(uname -r)): ${NC}"
    rpm -q kernel --queryformat '   - %{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V
    if [ "$(uname -r)" != "$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -n 1)" ]; then
        echo -e "${YELLOW}⚠️  运行中不是最新内核，建议手动重启进新内核后再装驱动。${NC}"
    fi

    # 硬件扫描（pciutils 最小化系统未必有，先保再扫）
    command -v lspci &>/dev/null || sudo dnf install -y pciutils
    # 自动检测出你是 AMD、Intel 还是 NVIDIA（或者两者都有，比如笔记本的核显+独显组合）
    echo -e "${CYAN}>> Scanning PCI buses for graphics hardware...${NC}"
    local gpu_info
    gpu_info=$(lspci | grep -iE 'vga|3d|display')
    
    echo -e "${YELLOW}--- Detected GPU Hardware ---${NC}"
    echo "$gpu_info" | while read -r line; do
        echo "  $line"
    done
    echo -e "${YELLOW}-----------------------------${NC}"

    # 自动分析特征
    local has_amd=false
    local has_intel=false
    local has_nvidia=false

    echo "$gpu_info" | grep -qi "amd\|radeon" && has_amd=true
    echo "$gpu_info" | grep -qi "intel" && has_intel=true
    echo "$gpu_info" | grep -qi "nvidia" && has_nvidia=true

    # SecureBoot 检查：akmod 默认不签名，开着 SB 进内核会被拒载——先告警，不硬拦
    if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
        echo -e "${RED}⚠️  SecureBoot 开启中：akmod 模块无签名会被内核拒载。${NC}"
        echo -e "${YELLOW}   二选一：BIOS 关 SB，或签模块（kmodgenca + mokutil --import），签完再重跑。${NC}"
    fi

    # 一级菜单
    echo -e "\n${CYAN}Based on the detection, how would you like to proceed?${NC}"
    echo "  1) ✅ Auto Confirm (Install drivers based on detection above)"
    echo "  2) ⚙️  Manual Selection (Choose specific iGPU/dGPU drivers)"
    echo "  0) ⏭️  Skip (Do not install any GPU drivers)"
    read -p "Select action [0/1/2]: " main_opt

    case "$main_opt" in
        0)
            echo -e "${YELLOW}>> User skipped GPU driver installation.${NC}"
            return 0
            ;;
        1)
            ensure_rpmfusion
            [ "$has_amd" = true ] && install_amd_drivers
            [ "$has_intel" = true ] && install_intel_drivers
            [ "$has_nvidia" = true ] && install_nvidia_drivers
            ;;
        2)
            ensure_rpmfusion
            # 二级菜单：核显 (iGPU)
            echo -e "\n${CYAN}--- [Manual] Select Integrated GPU (iGPU) ---${NC}"
            echo "  1) AMD Graphics (Installs mesa-freeworld)"
            echo "  2) Intel Graphics (Installs intel-media-driver)"
            echo "  0) Skip iGPU"
            read -p "Selection [0-2]: " igpu_opt
            case "$igpu_opt" in
                1) install_amd_drivers ;;
                2) install_intel_drivers ;;
                0) echo "Skipped iGPU." ;;
                *) echo -e "${RED}Invalid input, skipping iGPU.${NC}" ;;
            esac

            # 二级菜单：独显 (dGPU)
            echo -e "\n${CYAN}--- [Manual] Select Discrete GPU (dGPU) ---${NC}"
            echo "  1) AMD Radeon Dedicated"
            echo "  2) Intel ARC"
            echo "  3) NVIDIA GeForce/RTX (Installs akmod-nvidia & vaapi-bridge)"
            echo "  0) Skip dGPU"
            read -p "Selection [0-3]: " dgpu_opt
            case "$dgpu_opt" in
                1) install_amd_drivers ;; 
                2) install_intel_drivers ;;
                3) install_nvidia_drivers ;;
                0) echo "Skipped dGPU." ;;
                *) echo -e "${RED}Invalid input, skipping dGPU.${NC}" ;;
            esac
            ;;
        *)
            echo -e "${RED}❌ Invalid selection. Skipping GPU setup.${NC}"
            return 0
            ;;
    esac

    echo -e "\n${GREEN}✨ GPU Driver module completed!${NC}"
}

# 测试模式：如果直接运行这个文件，则触发函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_gpu_drivers
fi