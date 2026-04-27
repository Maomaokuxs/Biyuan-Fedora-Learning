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
    local GPU_SCRIPT="$REPO_DIR/scripts/03_gpu_drivers.sh"
    if [ -f "$GPU_SCRIPT" ]; then
        echo -e "${YELLOW}>> Loading external GPU driver configuration module...${NC}"
        chmod +x "$GPU_SCRIPT"
        source "$GPU_SCRIPT"
        if command -v setup_gpu &> /dev/null; then
            setup_gpu
        fi
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
    echo -e "${YELLOW}>> Installing Niri window manager and ecosystem components...${NC}"
    
    # 核心组件 + 终端 + 视觉引擎 + 工具 + 锁屏闲置管理
    # 新增: starship 已经加入列表
    local niri_pkgs=(
        niri waybar rofi-wayland fcitx5 fcitx5-chinese-addons
        stow unzip kitty fastfetch jq ImageMagick 
        swww hellwal waypaper polkit-kde
        hyprlock hypridle starship
    )

    echo -e "${YELLOW}>> Deploying Niri core and security tools...${NC}"
    sudo dnf install -y "${niri_pkgs[@]}"

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 5. 配置部署模式 (Stow 逻辑) ---
    echo -e "${YELLOW}==== Configuration Deployment Mode ====${NC}"
    echo "  1) ☁️  Sync Latest (Git -> Local) [Use Stow]"
    echo "  2) 📁  Physical Detachment (Restore physical files)"
    echo "  0) ⏭️  Skip"
    read -p "Select Mode [0-2]: " deploy_mode

    if [[ "$deploy_mode" =~ ^[1-2]$ ]]; then
        echo -e "${YELLOW}>> Executing configuration deployment...${NC}"
        for module in $(ls "$DOTFILES_DIR" 2>/dev/null); do
            local target_dir="$HOME/.config/$module"
            [[ "$module" == "colors" ]] && target_dir="$HOME/.cache/hellwal"
            [ -e "$target_dir" ] && rm -rf "$target_dir"

            if [ "$deploy_mode" == "1" ]; then
                cd "$DOTFILES_DIR" && stow -t ~ "$module" 2>/dev/null
                echo -e "  [🔗 Linked] $module"
            elif [ "$deploy_mode" == "2" ]; then
                mkdir -p "$target_dir"
                cp -rf "$DOTFILES_DIR/$module/." "$target_dir/"
                echo -e "  [📁 Physical] $module"
            fi
        done
        echo -e "${GREEN}✅ Configuration deployment complete!${NC}"

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