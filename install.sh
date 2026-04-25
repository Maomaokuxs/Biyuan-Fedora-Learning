#!/bin/bash

# --- 0. 基础路径与颜色 ---
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$REPO_DIR/dotfiles"
BACKUP_ROOT="$HOME/.dotfiles_backup"
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# --- 1. 实心大标题 (Block 字体) ---
if ! command -v figlet &> /dev/null; then sudo dnf install -y figlet &> /dev/null; fi
clear
echo -e "${BLUE}"
figlet -f block "BIYUAN"
figlet -f block "FEDORA"
echo -e "${NC}-----------------------------------------------------"
echo -e "       模块化环境向导程序 | 硬件驱动驱动版 | 2026.04"
echo -e "-----------------------------------------------------\n"

# --- 2. 核心：备份并部署函数 ---
deploy_module() {
    local module_name=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local bdir="$BACKUP_ROOT/${timestamp}_$module_name"

    local check_path=""
    if [ "$module_name" == "bash" ]; then
        check_path="$HOME/.bashrc"
    else
        check_path="$HOME/.config/$module_name"
    fi

    if [ -e "$check_path" ]; then
        echo -e "${YELLOW}>> 正在备份旧配置: $module_name -> $bdir${NC}"
        mkdir -p "$bdir"
        cp -rf "$check_path" "$bdir/"
    fi

    cd "$DOTFILES_DIR"
    if stow -v -t ~ "$module_name" 2>/dev/null; then
        echo -e "${GREEN}✅ $module_name 配置关联成功。${NC}"
    else
        echo -e "${RED}❌ $module_name 映射失败，请检查仓库目录。${NC}"
    fi
}

# --- 3. [STEP 1/4] 系统快照基建 ---
setup_snapper() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [STEP 1/4] 系统底层保护：Snapper 快照配置${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    if ! command -v snapper &> /dev/null; then
        sudo dnf install -y snapper
    fi

    echo -e "正在检测可创建快照的 Btrfs 子卷...\n"
    mapfile -t subvolumes < <(findmnt -nt btrfs -o TARGET)

    if [ ${#subvolumes[@]} -eq 0 ]; then
        echo -e "${RED}未检测到 Btrfs 挂载点，跳过配置。${NC}\n"
        return
    fi

    local default_indices=""
    for i in "${!subvolumes[@]}"; do
        local clean_path=$(echo "${subvolumes[i]}" | sed 's/[^/]*//')
        if [[ "$clean_path" == "/" || "$clean_path" == "/home" ]]; then
            default_indices+="$((i+1)) "
        fi
    done
    default_indices=$(echo "$default_indices" | xargs)

    echo -e "发现以下 Btrfs 挂载点:"
    for i in "${!subvolumes[@]}"; do
        echo "  $((i+1))) ${subvolumes[i]}"
    done
    echo "  0) 跳过此步骤"
    
    local prompt_text="请输入选项数字 (多选请用空格隔开"
    if [ -n "$default_indices" ]; then
        prompt_text+="，直接回车默认选取 [$default_indices]): "
    else
        prompt_text+="): "
    fi

    read -p "$prompt_text" choices

    if [[ -z "$choices" ]]; then
        if [[ -n "$default_indices" ]]; then
            choices="$default_indices"
            echo -e "${YELLOW}>> 默认选取了: $choices${NC}"
        else
            echo -e "未找到 / 或 /home，且未选择任何项，已跳过此步骤。\n"; return
        fi
    fi

    for idx in $choices; do
        if [[ "$idx" == "0" ]]; then
            echo -e "已跳过快照配置。\n"; return
        fi
        
        if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#subvolumes[@]}" ]; then
            echo -e "${RED}警告: 选项 '$idx' 无效，已跳过。${NC}"
            continue
        fi

        local sub_display="${subvolumes[$((idx-1))]}"
        local clean_sub=$(echo "$sub_display" | sed 's/[^/]*//')
        local config_name=$(echo "$clean_sub" | sed 's/\///g')
        [ -z "$config_name" ] && config_name="root"
        
        echo -e "\n${BLUE}--- 正在处理挂载点: $sub_display ---${NC}"
        
        if [ -f "/etc/snapper/configs/$config_name" ]; then
            echo -e "${YELLOW}警告: 挂载点 $clean_sub 已有名为 '$config_name' 的配置。${NC}"
            read -p "是否重新配置？(将会删除旧配置并重建) [y/N]: " reconf
            if [[ $reconf != [yY] ]]; then
                echo ">> 保留现有配置，跳过 $clean_sub。"
                continue
            else
                sudo snapper -c "$config_name" delete-config
            fi
        fi

        echo -e "${YELLOW}正在创建 Snapper 配置: $config_name${NC}"
        if sudo snapper -c "$config_name" create-config "$clean_sub"; then
            echo -e "${GREEN}✅ $sub_display 快照配置完成。${NC}"
        else
            echo -e "${RED}❌ $sub_display 快照配置失败！${NC}"
        fi
    done
    echo "" 
}

# --- 4. [STEP 2/4] 硬件显卡驱动 ---
setup_gpu() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [STEP 2/4] 硬件底层解析：显卡驱动与加速引擎${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    echo "  1) NVIDIA 闭源驱动 (自动配置 RPM Fusion)"
    echo "  2) AMD Radeon (附加 Vulkan & 视频编解码加速)"
    echo "  3) Intel 核显/独显 (附加 Vulkan & 视频编解码加速)"
    echo "  0) 跳过此步骤 (使用系统默认开源驱动)"
    
    read -p "请选择你的显卡平台 [0-3]: " gpu_opt
    gpu_opt=${gpu_opt:-0}

    if [[ "$gpu_opt" == "0" ]]; then
        echo -e "已跳过显卡驱动安装。\n"
        return
    fi

    echo -e "\n${YELLOW}>> 确认安装对应的硬件加速支持包吗？[y/N]: ${NC}\c"
    read confirm
    if [[ $confirm != [yY] ]]; then
        echo -e "已取消安装。\n"; return
    fi

    case $gpu_opt in
        1)
            echo -e "${YELLOW}正在配置 RPM Fusion 并安装 NVIDIA 闭源驱动...${NC}"
            # 自动导入 RPM Fusion 源（Nvidia 刚需）
            sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
            # 安装驱动和 CUDA 支持
            sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
            echo -e "${GREEN}✅ NVIDIA 驱动安装完成。(注意：需在整个脚本结束后重启生效)${NC}"
            ;;
        2)
            echo -e "${YELLOW}正在为 AMD 显卡补全 Vulkan 与硬件解码...${NC}"
            sudo dnf install -y mesa-vulkan-drivers mesa-va-drivers rocm-opencl radeontop
            echo -e "${GREEN}✅ AMD 增强包安装完成。${NC}"
            ;;
        3)
            echo -e "${YELLOW}正在为 Intel 显卡补全 Vulkan 与硬件解码...${NC}"
            sudo dnf install -y mesa-vulkan-drivers intel-media-driver
            echo -e "${GREEN}✅ Intel 增强包安装完成。${NC}"
            ;;
        *)
            echo -e "${RED}无效选项。${NC}"
            ;;
    esac
    echo ""
}

# --- 5. [STEP 3/4] 基础环境部署 ---
setup_base() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [STEP 3/4] 核心基建：基础系统与终端环境${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    read -p "同步 Bash/Starship 并安装基础工具 (git, curl 等)? [y/N]: " res
    if [[ $res == [yY] ]]; then
        deploy_module "bash"
        deploy_module "starship"
        sudo dnf install -y git curl fastfetch htop stow starship
        echo -e "${GREEN}基础环境已就绪。${NC}\n"
    else
        echo -e "已跳过基础环境部署。\n"
    fi
}

# --- 6. [STEP 4/4] 桌面环境集成 ---
setup_desktop() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [STEP 4/4] 视觉交互：Niri 桌面环境与组件${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    while true; do
        echo "  1) Niri WM (核心窗口管理器)"
        echo "  2) Waybar (状态栏)"
        echo "  3) Rofi (启动器)"
        echo "  4) Hypr-utils (锁屏与空闲管理)"
        echo "  5) 全部安装并映射 (默认推荐)"
        echo "  0) 结束并退出向导"
        
        read -p "请输入选项 [默认 5]: " sub_opt
        sub_opt=${sub_opt:-5}

        if [[ "$sub_opt" == "0" ]]; then
            break
        fi

        echo -e "\n${YELLOW}>> 您选择了选项: $sub_opt${NC}"
        read -p "确认执行此部署任务吗？[y/N]: " confirm
        if [[ $confirm != [yY] ]]; then
            echo -e "已取消，请重新选择。\n"; continue
        fi

        case $sub_opt in
            1) sudo dnf install -y niri && deploy_module "niri" ;;
            2) sudo dnf install -y waybar && deploy_module "waybar" ;;
            3) sudo dnf install -y rofi-wayland && deploy_module "rofi" ;;
            4) sudo dnf install -y hypridle hyprlock && deploy_module "hypr" ;;
            5) 
                sudo dnf install -y niri waybar rofi-wayland hypridle hyprlock python3-pywal
                deploy_module "niri"; deploy_module "waybar"; deploy_module "rofi"; deploy_module "hypr"
                ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac
        echo -e "${GREEN}>> 组件部署任务完成，你可以继续补充安装或按 0 退出。${NC}\n"
    done
}

# --- 执行主程序向导 ---
setup_snapper
setup_gpu
setup_base
setup_desktop

echo -e "\n${BLUE}✨ 所有环境部署完毕！祝你的系统稳如磐石，桌面赏心悦目！${NC}\n"