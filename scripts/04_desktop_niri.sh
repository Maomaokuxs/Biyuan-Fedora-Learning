#!/bin/bash
# 文件位置: scripts/04_desktop_niri.sh

install_desktop_niri() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 3] Niri 桌面环境自动化部署${NC}"
    echo -e "${BLUE}=====================================================${NC}"

    # --- 1. 【新增】调用基础环境脚本 ---
    local BASE_SCRIPT="$REPO_DIR/scripts/02_base_env.sh"
    if [ -f "$BASE_SCRIPT" ]; then
        echo -e "${YELLOW}>> 正在检查并部署基础运行环境...${NC}"
        chmod +x "$BASE_SCRIPT"
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

    # --- 3. 安装 Niri 及核心周边组件 ---
    echo -e "${YELLOW}>> 正在安装 Niri 窗口管理器及周边生态环境...${NC}"
    # 移除已在 base_env 中安装过的包，保持精简
    sudo dnf install -y niri waybar rofi-wayland fcitx5 fcitx5-chinese-addons
    echo -e "${GREEN}✅ 桌面核心组件安装完毕。${NC}"

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 4. 配置部署模式 (Stow 逻辑) ---
    echo -e "${YELLOW}==== 初始配置部署模式 ====${NC}"
    echo "  1) ☁️  同步仓库最新配置 (Git -> Local) [使用 Stow]"
    echo "  2) 📁  物理脱离 (还原物理文件)"
    echo "  0) ⏭️  跳过"
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
        echo -e "${GREEN}✅ 配置文件部署完毕！${NC}"

        # --- 5. 自动化色彩与壁纸初始化 ---
        local INIT_SCRIPT="$HOME/.config/niri/scripts/init-wallpaper.sh"
        if [ -f "$INIT_SCRIPT" ]; then
            echo -e "${BLUE}>> 正在激活视觉引擎...${NC}"
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
        echo -e "${GREEN}✅ 命令部署成功。${NC}"
    fi
}