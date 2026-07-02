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
    # 核心：niri (窗口管理器), waybar (状态栏), rofi-wayland (启动器)
    # 美化：swww (壁纸后端), hellwal (色彩方案生成), starship (终端美化)，cava（终端可视化音乐实现）
    # 功能：fcitx5 (输入法), nautilus (文件管理), mako (通知通知), hyprlock/idle (锁屏与休眠)，loupe（图片查看器），
    # blueman（蓝牙管理工具），btop（资源占用查看工具)，gnome-text-editor（文本编辑器）,ddcutil(显示器亮度调整)，nmtui（网络连接工具）
    # seahorse gnome-keyring libsecret（密钥及管理工具）ncdu(终端磁盘文件占用查看器) ranger（终端文件管理器）
    
    local niri_pkgs=(
        niri waybar rofi-wayland stow unzip kitty 
        fastfetch jq ImageMagick swww hellwal 
        waypaper starship hyprlock hypridle 
        gpu-screen-recorder libnotify mako 
        fcitx5 fcitx5-chinese-addons 
        xdg-desktop-portal-gnome xdg-desktop-portal-wlr
        polkit-kde firefox cava nautilus loupe nautilus-python
        blueman btop gnome-text-editor ddcutil nmtui 
        seahorse gnome-keyring libsecret ncdu ranger
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
                    [ -L "$target_dir" ] && rm -f "$target_dir"
                    
                    # 如果之前是物理文件夹，先清空，防止文件交错残留
                    [ -d "$target_dir" ] && rm -rf "$target_dir"
                    
                    # 3. 安全物理拷贝
                    cp -a "$DOTFILES_DIR/$module/." "$HOME/" 2>/dev/null
                    echo -e "  [📁 Physical] $module"
                done
                echo -e "${GREEN}✅ Configuration physical detachment complete!${NC}"
                # 同步 starship 模板到 by-mgr 本地模板库
                if [ -f "$DOTFILES_DIR/starship/.config/starship_base.toml" ]; then
                    mkdir -p "$HOME/.config/by-mgr/templates"
                    cp -aL "$DOTFILES_DIR/starship/.config/starship_base.toml" "$HOME/.config/by-mgr/templates/"
                    echo -e "${GREEN}✅ Starship template cached to by-mgr templates.${NC}"
                fi
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

    # --- 7. 注册全局维护命令 by-mgr 与 Shell 环境初始化 ---
    echo -e "${BLUE}>> Registering global commands and initializing shell...${NC}"
    local BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    
    if [ -f "$REPO_DIR/scripts/by-mgr" ]; then
        # 1. 部署 by-mgr 工具
        cp "$REPO_DIR/scripts/by-mgr" "$BIN_DIR/by-mgr"
        chmod +x "$BIN_DIR/by-mgr"
        
        # 定义配置文件路径
        local BASH_RC="$HOME/.bashrc"
        local ZSH_RC="$HOME/.zshrc"
        local BASH_PROFILE="$HOME/.bash_profile"
        
        # --- A. 注入 PATH 与 Starship (针对交互式 Shell) ---
        for rc in "$BASH_RC" "$ZSH_RC"; do
            if [ -f "$rc" ]; then
                local PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""
                local STARSHIP_CMD='eval "$(starship init '$(basename "$rc" | sed 's/rc//;s/\.//')')"'
                
                # 注入 PATH
                if ! grep -Fq "$PATH_LINE" "$rc"; then
                    echo -e "\n# Biyuan CLI Tools & Environment" >> "$rc"
                    echo "$PATH_LINE" >> "$rc"
                fi
                
                # 注入 Starship
                if ! grep -Fq "starship init" "$rc"; then
                    echo -e "\n# Starship Prompt Initialization" >> "$rc"
                    echo "$STARSHIP_CMD" >> "$rc"
                fi
            fi
        done

        echo -e "${GREEN}✅ Command and Shell environment deployed successfully.${NC}"
    else
        echo -e "${RED}❌ Error: by-mgr script not found at $REPO_DIR/scripts/by-mgr${NC}"
    fi

    # --- 8. 登录管理器部署 (极简双选菜单) ---
    while true; do
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}>> Please select the Display Manager configuration:${NC}"
        echo -e "   ${CYAN}[1]${NC} greetd + tuigreet (Modern/Minimalist - Perfect for Niri)"
        echo -e "   ${CYAN}[2]${NC} Skip / Keep Current (Do not install any display manager)"
        echo -e "${BLUE}==================================================${NC}"
        echo -n -e "${YELLOW}?? Enter your choice [1-2]: ${NC}"
        
        read -r dm_choice
        
        case "$dm_choice" in
            1)
                # 【核心修正】：将独立脚本文件名从 05 精确映射为 07_greetd_setup.sh
                local GREETD_SCRIPT="$REPO_DIR/scripts/07_greetd_setup.sh"
                if [ -f "$GREETD_SCRIPT" ]; then
                    echo -e "${YELLOW}>> Deploying greetd/tuigreet...${NC}"
                    source "$GREETD_SCRIPT"
                    setup_greetd_niri
                else
                    echo -e "${RED}❌ ERROR: Setup script not found at $GREETD_SCRIPT!${NC}"
                fi
                break
                ;;
            2)
                echo -e "${GREEN}>> Skipped display manager deployment. Keeping your current system state.${NC}"
                # 显式重置全局或父级变量，避免主脚本尾部拦截器误判
                export dm_choice="2"
                break
                ;;
            *)
                echo -e "${RED}❌ Invalid input! Please choose [1-2]...${NC}"
                echo ""
                ;;
        esac
    done
}