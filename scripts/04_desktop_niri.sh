#!/bin/bash
# 文件位置: scripts/04_desktop_niri.sh

install_desktop_niri() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [Phase 3] Niri Desktop Environment Deployment${NC}"
    echo -e "${BLUE}=====================================================${NC}"

    # --- 1. 调用基础环境脚本 ---
    local BASE_SCRIPT="$REPO_DIR/scripts/02_base_env.sh"
    if [ -f "$BASE_SCRIPT" ]; then
        echo -e "${YELLOW}>> Checking and deploying base runtime environment...${NC}"
        chmod +x "$BASE_SCRIPT"
        source "$BASE_SCRIPT"
        if command -v setup_base &> /dev/null; then
            setup_base
        fi
    fi

    # --- 2. 调用独立显卡驱动脚本 ---
    # 增加兜底：如果 REPO_DIR 没传过来，默认找当前目录的 scripts
    local GPU_SCRIPT="${REPO_DIR:-$HOME/Documents/github/Biyuan-Fedora-Learning}/scripts/03_gpu_drivers.sh"
    
    if [ -f "$GPU_SCRIPT" ]; then
        echo -e "${YELLOW}>> Loading external GPU driver configuration module...${NC}"
        chmod +x "$GPU_SCRIPT"
        source "$GPU_SCRIPT"
        
        # 【核心修正】：调用的函数名必须与 03 脚本里的定义完全一致
        if command -v setup_gpu_drivers &> /dev/null; then
            setup_gpu_drivers
        else
            echo -e "${RED}❌ Error: 'setup_gpu_drivers' function not found in 03_gpu_drivers.sh!${NC}"
        fi
    else
        echo -e "${RED}❌ Error: Cannot find GPU script at $GPU_SCRIPT${NC}"
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 3. 配置三方仓库 (新增 Starship 仓库) ---
    echo -e "${BLUE}>> Enabling visual engine and desktop component repository...${NC}"
    
    # 启用 Hyprland 兼容生态仓库
    sudo dnf copr enable -y hermitfeather/hyprland
    
    # 新增: 启用 Starship 官方 Copr 仓库
    echo -e "${YELLOW}>> Enabling Starship shell prompt repository...${NC}"
    if sudo dnf copr enable -y atim/starship; then
        echo -e "${GREEN}✅ Repository [atim/starship] enabled.${NC}"
    else
        echo -e "${RED}❌ Failed to enable Starship repository.${NC}"
    fi

    # --- 4. 安装 Niri 及桌面/视觉生态组件 ---
    echo -e "${YELLOW}>> Setting up multimedia and recording environment...${NC}"
    
    # 1. 优先解决 FFmpeg 冲突 (录屏工具的基石)
    if rpm -q ffmpeg-free &>/dev/null; then
        echo -e "${CYAN}>> Swapping to full-featured ffmpeg for NVENC support...${NC}"
        sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    fi

    # 2. 启用专用录屏仓库
    echo -e "${CYAN}>> Enabling gpu-screen-recorder COPR repository...${NC}"
    sudo dnf copr enable -y ackerman/nexus

    # 3. 执行补全安装
    # 包含了之前可能被中断的 mako 和 dolphin
    local niri_pkgs=(
        niri waybar rofi-wayland stow unzip kitty 
        fastfetch jq ImageMagick swww hellwal 
        waypaper starship hyprlock hypridle 
        gpu-screen-recorder libnotify mako 
        dolphin fcitx5 fcitx5-chinese-addons 
        xdg-desktop-portal-gnome xdg-desktop-portal-wlr
        libva-nvidia-driver libva-utils libva-nvidia-driver
    )

    echo -e "${YELLOW}>> Deploying Niri ecosystem components...${NC}"
    # 使用 --skip-unavailable 增强容错性
    sudo dnf install -y "${niri_pkgs[@]}" --skip-unavailable

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"
    
    # --- 5. 配置部署模式 (Stow 逻辑) ---
    echo -e "\n${YELLOW}==== Configuration Deployment Mode ====${NC}"
    echo "  1) ☁️  Sync Latest (Git -> Local) [Use Stow]"
    echo "  2) 📁  Physical Detachment (Restore physical files)"
    echo "  0) ⏭️  Skip (Keep current system configs unchanged)"
    
    # 强制单选循环
    while true; do
        read -p "Select Mode [0/1/2]: " deploy_mode
        
        case "$deploy_mode" in
            1)
                echo -e "${YELLOW}>> Executing Stow configuration deployment (Symlink)...${NC}"
                for module in $(ls "$DOTFILES_DIR" 2>/dev/null); do
                    # 1. 尝试让 stow 回收旧链接 (如果以前链接过)
                    cd "$DOTFILES_DIR" && stow -D -t ~ "$module" 2>/dev/null
                    
                    # 2. 强力清理同名物理文件夹 (防止 stow 冲突报错)
                    local target_dir="$HOME/.config/$module"
                    [[ "$module" == "colors" ]] && target_dir="$HOME/.cache/hellwal"
                    [ -d "$target_dir" ] && [ ! -L "$target_dir" ] && rm -rf "$target_dir"

                    # 3. 重新建立干净的软链接
                    cd "$DOTFILES_DIR" && stow -t ~ "$module" 2>/dev/null
                    echo -e "  [🔗 Linked] $module"
                done
                echo -e "${GREEN}✅ Configuration deployment complete!${NC}"
                break
                ;;
            2)
                echo -e "${YELLOW}>> Executing Physical configuration deployment (Copy)...${NC}"
                for module in $(ls "$DOTFILES_DIR" 2>/dev/null); do
                    # 【核心修复】：彻底销毁旧的软链接
                    # 1. 尝试让 stow 回收旧链接
                    cd "$DOTFILES_DIR" && stow -D -t ~ "$module" 2>/dev/null
                    
                    # 2. 暴力拔除（防止由于路径变动导致 stow 无法识别的“死链接”）
                    local target_dir="$HOME/.config/$module"
                    [[ "$module" == "colors" ]] && target_dir="$HOME/.cache/hellwal"
                    [ -L "$target_dir" ] && rm -f "$target_dir"
                    
                    # 如果之前是物理文件夹，先清空，防止文件交错残留
                    [ -d "$target_dir" ] && rm -rf "$target_dir"
                    
                    # 3. 安全物理拷贝
                    cp -a "$DOTFILES_DIR/$module/." "$HOME/" 2>/dev/null
                    echo -e "  [📁 Physical] $module"
                done
                echo -e "${GREEN}✅ Configuration physical detachment complete!${NC}"
                break
                ;;
            0)
                # 严格跳过机制：不做任何复制、删除和链接操作
                echo -e "${YELLOW}>> Skipped configuration deployment. No custom files were modified.${NC}"
                break
                ;;
            *)
                # 捕获非法输入
                echo -e "${RED}❌ Invalid selection. Please enter exactly 0, 1, or 2.${NC}"
                ;;
        esac
    done

# --- 6. 自动化色彩与壁纸初始化 ---
        local INIT_SCRIPT="$HOME/.config/niri/scripts/init-wallpaper.sh"
        if [ -f "$INIT_SCRIPT" ]; then
            echo -e "${BLUE}>> Activating visual engine...${NC}"
            chmod +x "$INIT_SCRIPT"
            bash "$INIT_SCRIPT"
        else
            local ALT_INIT="$DOTFILES_DIR/niri/.config/niri/scripts/init-wallpaper.sh"
            if [ -f "$ALT_INIT" ]; then
                chmod +x "$ALT_INIT"
                bash "$ALT_INIT"
            fi
        fi


    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 7. 注册全局维护命令 by-mgr ---
    echo -e "${BLUE}>> Registering global maintenance command: by-mgr${NC}"
    local BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    
    if [ -f "$REPO_DIR/scripts/by-mgr" ]; then
        cp "$REPO_DIR/scripts/by-mgr" "$BIN_DIR/by-mgr"
        chmod +x "$BIN_DIR/by-mgr"
        
        local SHELL_RC="$HOME/.bashrc"
        [[ "$SHELL" == *"zsh"* ]] && SHELL_RC="$HOME/.zshrc"
        
        local PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""
        if [ -f "$SHELL_RC" ]; then
            if ! grep -Fq "$PATH_LINE" "$SHELL_RC"; then
                echo -e "\n# Biyuan CLI Tools" >> "$SHELL_RC"
                echo "$PATH_LINE" >> "$SHELL_RC"
            fi
        fi
        echo -e "${GREEN}✅ Command deployed successfully.${NC}"
    fi

    # --- 8. 登录管理器部署 (修正: 移入函数体内) ---
    local GREETD_SCRIPT="$REPO_DIR/scripts/05_greetd_setup.sh"
    if [ -f "$GREETD_SCRIPT" ]; then
        echo -e "${YELLOW}>> Configuring display manager (greetd/tuigreet)...${NC}"
        source "$GREETD_SCRIPT"
        setup_greetd_niri
    fi
}