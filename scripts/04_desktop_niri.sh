#!/bin/bash
# 文件位置: scripts/04_desktop_niri.sh

install_desktop_niri() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 2] 显卡驱动探测与 Niri 桌面部署${NC}"
    echo -e "${BLUE}=====================================================${NC}"

    # --- 1. 智能显卡硬件检测与驱动安装 ---
    echo -e "${YELLOW}>> 正在扫描本机显卡硬件...${NC}"
    
    # 使用 lspci 抓取 VGA/3D 控制器信息
    GPU_INFO=$(lspci | grep -iE 'vga|3d')
    echo -e "${CYAN}发现图形硬件: ${GPU_INFO}${NC}"

    if echo "$GPU_INFO" | grep -iq "nvidia"; then
        echo -e "${YELLOW}>> 检测到 NVIDIA 显卡。准备安装专有驱动与内核模块 (akmod)...${NC}"
        echo -e "${BLUE}ℹ️  提示: 安装 akmod-nvidia 前会自动更新系统内核，以确保模块编译成功。${NC}"
        
        sudo dnf update -y
        # 安装 NVIDIA 驱动、CUDA 依赖以及 Wayland 支持包
        sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda egl-wayland
        
        echo -e "${GREEN}✅ NVIDIA 驱动安装指令已执行。(需重启后生效)${NC}"

    elif echo "$GPU_INFO" | grep -iq "amd"; then
        echo -e "${GREEN}✅ 检测到 AMD 显卡。Fedora 内置的开源驱动 (amdgpu/Mesa) 已完美支持 Wayland，无需额外安装专有驱动。${NC}"
    elif echo "$GPU_INFO" | grep -iq "intel"; then
        echo -e "${GREEN}✅ 检测到 Intel 显卡。内置开源驱动已就绪。${NC}"
    else
        echo -e "${YELLOW}⚠️  未匹配到特定独立显卡型号，将使用系统默认驱动栈。${NC}"
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 2. 安装 Niri 及核心组件 ---
    echo -e "${YELLOW}>> 正在安装 Niri 窗口管理器及周边生态环境...${NC}"
    # 推荐安装 rofi-wayland 替代原版 rofi 以获得更好的原生体验
    sudo dnf install -y niri waybar rofi-wayland kitty fcitx5 fcitx5-chinese-addons stow
    echo -e "${GREEN}✅ 基础软件包安装完毕。${NC}"

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 3. Biyuan 极简配置部署菜单 (二选一) ---
    echo -e "${YELLOW}==== 初始配置部署模式 ====${NC}"
    echo "  1) ☁️  同步仓库最新配置 (Git -> Local) [推荐：使用 Stow 软链接]"
    echo "  2) 📁  物理脱离 (断开链接并还原物理文件) [用于独立测试]"
    echo "  0) ⏭️  跳过配置部署"
    read -p "选择模式 [0-2]: " deploy_mode

    if [[ "$deploy_mode" =~ ^[1-2]$ ]]; then
        echo -e "${YELLOW}>> 正在执行配置部署...${NC}"
        
        for module in $(ls "$DOTFILES_DIR" 2>/dev/null); do
            local target_dir="$HOME/.config/$module"
            [[ "$module" == "colors" ]] && target_dir="$HOME/.cache/hellwal"

            # 预清理可能存在的冲突
            [ -e "$target_dir" ] && rm -rf "$target_dir"

            if [ "$deploy_mode" == "1" ]; then
                cd "$DOTFILES_DIR" && stow -t ~ "$module" 2>/dev/null
                echo -e "  [🔗 链接] $module"
            elif [ "$deploy_mode" == "2" ]; then
                mkdir -p "$target_dir"
                cp -rf "$DOTFILES_DIR/$module/." "$target_dir/"
                echo -e "  [📁 物理] $module"
            fi
        done
        echo -e "${GREEN}✅ 所有的配置文件部署完毕！${NC}"
    else
        echo -e "${YELLOW}>> 已跳过配置文件部署。${NC}"
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 4. 注册全局维护命令 by-mgr ---
    echo -e "${BLUE}>> 正在注册全局系统维护命令: by-mgr${NC}"
    local BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    
    if [ -f "$REPO_DIR/scripts/by-mgr" ]; then
        cp "$REPO_DIR/scripts/by-mgr" "$BIN_DIR/by-mgr"
        chmod +x "$BIN_DIR/by-mgr"
        
        local SHELL_RC="$HOME/.bashrc"
        [[ $SHELL == *"zsh"* ]] && SHELL_RC="$HOME/.zshrc"
        
        if ! grep -q "$BIN_DIR" "$SHELL_RC"; then
            echo -e "\n# Biyuan CLI Tools" >> "$SHELL_RC"
            echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
        fi
        echo -e "${GREEN}✅ 命令部署成功。以后可直接输入 'by-mgr' 唤起高级维护菜单！${NC}"
    else
        echo -e "${RED}⚠️ 警告: 找不到 scripts/by-mgr，跳过命令部署。请检查文件是否存在。${NC}"
    fi
}