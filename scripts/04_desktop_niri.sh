#!/bin/bash
# 文件位置: scripts/04_desktop_niri.sh

install_desktop_niri() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 2] Niri 桌面环境自动化部署${NC}"
    echo -e "${BLUE}=====================================================${NC}"

    # --- 1. [核心新增] 自动触发基础环境安装 ---
    # 确保在安装桌面之前，base 环境里的 stow, jq, hellwal 等全部装好
    local BASE_SCRIPT="$REPO_DIR/scripts/02_base_env.sh"
    if [ -f "$BASE_SCRIPT" ]; then
        source "$BASE_SCRIPT"
        if command -v setup_base &> /dev/null; then
            setup_base
        fi
    fi

    # --- 2. 调用独立显卡驱动脚本 ---
    local GPU_SCRIPT="$REPO_DIR/scripts/03_gpu_drivers.sh"
    if [ -f "$GPU_SCRIPT" ]; then
        echo -e "${YELLOW}>> 正在加载外部显卡驱动配置模块...${NC}"
        chmod +x "$GPU_SCRIPT"
        source "$GPU_SCRIPT"
        if command -v setup_gpu &> /dev/null; then
            setup_gpu
        fi
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 3. 安装 Niri 及核心组件 ---
    echo -e "${YELLOW}>> 正在安装 Niri 窗口管理器及周边生态环境...${NC}"
    # 增加了一些 Niri 常用工具：mako (通知), cava (频谱)
    sudo dnf install -y niri waybar rofi-wayland kitty fcitx5 fcitx5-chinese-addons stow mako cava
    echo -e "${GREEN}✅ Niri 核心软件包安装完毕。${NC}"

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 4. Biyuan 极简配置部署菜单 (Stow 逻辑) ---
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

        # --- 5. 自动化色彩与壁纸初始化 ---
        local INIT_SCRIPT="$HOME/.config/niri/scripts/init-wallpaper.sh"
        if [ -f "$INIT_SCRIPT" ]; then
            echo -e "${BLUE}>> 正在激活视觉引擎 (Hellwal Sync)...${NC}"
            chmod +x "$INIT_SCRIPT"
            bash "$INIT_SCRIPT"
        fi
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 6. 注册全局维护命令 by-mgr ---
    echo -e "${BLUE}>> 正在注册全局系统维护命令: by-mgr${NC}"
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
        echo -e "${GREEN}✅ by-mgr 命令部署成功。${NC}"
    fi
}